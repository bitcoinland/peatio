namespace :snapshot do

  task dns: :environment do
    pts_addresses = CoinRPC['pts'].listaddressgroupings.flatten(1).map(&:first)

    genesis_keyid_file = File.open ENV['DATA']
    json = JSON.load genesis_keyid_file

    allocations = {}
    json['balances'].each {|item| allocations[item[0]] = item[1] }

    sum = 0
    hit = 0
    pts_addresses.each do |addr|
      if allocations[addr]
        sum += allocations[addr]
        hit += 1
      end
    end
    sum = sum / 100000000.0
    puts "Total allocations by #{hit} addresses: #{sum}"

    pts_id = Currency.find_by_code('pts').id
    versions = AccountVersion.find_by_sql <<-SQL
      SELECT * FROM account_versions WHERE id IN
      ( SELECT max(id) FROM account_versions WHERE created_at < '2014-08-22' AND currency = "#{pts_id}" GROUP BY account_id )
    SQL

    pts = 0
    total = 0
    hit = 0
    versions.each do |v|
      m = v.account.member

#      acc = m.ac('btsx')
#      amount = v.amount * 500
#
#      #puts "plus funds #{amount} for account##{acc.id}"
#      #acc.plus_funds amount, reason: Account::DEPOSIT
#      #m.deposits.create account: acc, currency: 'btsx', amount: amount, fund_uid: 'pts', fund_extra: 'snapshot', txid: "yunbi#{acc.id}"
#      puts "#{m.id} #{m.display_name} #{m.email} #{v.amount} #{amount} #{acc.id}"

      if v.amount > 0
        pts += v.amount
        dns = v.amount*1176
        total += dns
        hit += 1
        puts("User#%5d %-40s %-20s => %-20s" % [m.id, "#{m.name} <#{m.email}>", "#{v.amount.to_s('F')} PTS", "#{dns.to_s('F')} DNS"])
      end
    end

    puts "#{pts.to_s('F')} PTS in #{hit} accounts requires #{total.to_s('F')} DNS."
    puts "DNS pool: #{sum} DNS"
  end

  desc "calculate member active order voulme percentage of ME snapshot"
  task member_volume: :environment do
    ask_orders = Hash.new{|h,k| h[k] = 0}
    bid_orders = Hash.new{|h,k| h[k] = 0}
    File.readlines('/tmp/limit_orderbook_btccny').each do |line|
      line.strip!
      current = nil
      case line.strip
      when /(\d+)\/\$([0-9.]+)\/([0-9.]+)/
        order = Order.find $1
        volume = BigDecimal.new $3
        if order.is_a?(OrderAsk)
          ask_orders[order.member_id] += volume
        else
          bid_orders[order.member_id] += volume*order.price
        end
      else
        puts "skip line: #{line}"
      end
    end

    asks = ask_orders.map do |mid, amount|
      m = Member.find mid
      [m.id, m.email, m.accounts.with_currency(:btc).first.payment_address.address, amount]
    end
    bids = bid_orders.map do |mid, amount|
      m = Member.find mid
      [m.id, m.email, m.accounts.with_currency(:btc).first.payment_address.address, amount]
    end

    asks_total = asks.map(&:last).reduce(&:+)
    bids_total = bids.map(&:last).reduce(&:+)

    asks.each{|ask| ask << (ask.last / asks_total).round(8) }
    bids.each{|bid| bid << (bid.last / bids_total).round(8) }

    IO.write Rails.root.to_s + '/asks.csv', asks.collect{|item| item.join(',')}.join("\n")
    IO.write Rails.root.to_s + '/bids.csv', bids.collect{|item| item.join(',')}.join("\n")
  end

  desc "snapshot of orderbook"
  task orderbook: :environment do
    asks = []
    OrderAsk.active.with_currency('btccny').group_by(&:member_id).each do |mid, orders|
      amount = orders.map(&:volume).reduce(&:+)
      m = Member.find mid
      asks << [m.id, m.email, amount]
    end

    bids = []
    OrderBid.active.with_currency('btccny').group_by(&:member_id).each do |mid, orders|
      amount = orders.collect{|order| order.volume * order.price }.reduce(&:+)
      m = Member.find mid
      bids << [m.id, m.email, amount]
    end

    asks_total = asks.map(&:last).reduce(&:+)
    bids_total = bids.map(&:last).reduce(&:+)

    asks.each{|ask| ask << (ask.last / asks_total).round(8) }
    bids.each{|bid| bid << (bid.last / bids_total).round(8) }

    IO.write Rails.root.to_s + '/asks.csv', asks.collect{|item| item.join(',')}.join("\n")
    IO.write Rails.root.to_s + '/bids.csv', bids.collect{|item| item.join(',')}.join("\n")
  end

end
