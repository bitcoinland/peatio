module Worker
  class WithdrawCoin

    def process(payload, metadata, delivery_info)
      payload.symbolize_keys!

      Withdraw.transaction do
        withdraw = Withdraw.lock.find payload[:id]

        return unless withdraw.processing?

        withdraw.whodunnit('Worker::WithdrawCoin') do
          withdraw.call_rpc!
        end
      end

      Withdraw.transaction do
        withdraw = Withdraw.lock.find payload[:id]

        return unless withdraw.almost_done?

        balance = CoinRPC[withdraw.currency].getbalance.to_d
        raise Account::BalanceError, 'Insufficient coins' if balance < withdraw.sum

        fee = [withdraw.fee.to_f || withdraw.channel.try(:fee) || 0.0005, 0.1].min

        CoinRPC[withdraw.currency].settxfee fee.to_f
        txid = CoinRPC[withdraw.currency].sendtoaddress *withdraw.sendtoaddress_args

        withdraw.whodunnit('Worker::WithdrawCoin') do
          withdraw.update_column :txid, txid
          withdraw.succeed!
          #TODO: Find the reason why 'withdraw.succeed!' desn't trigger after_commit callback in Account model.
          withdraw.account.send(:sync_update)
        end
      end
    end

  end
end
