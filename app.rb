# frozen_string_literal: true

ENV['RACK_ENV'] ||= 'development'

require 'sinatra'
require_relative 'db'

post '/operation' do
  data = JSON.parse(request.body.read)

  user = User.eager(:template).with_pk(data['user_id'])
  if user.nil?
    halt(*json_error("User id=#{data['user_id']} not found", code: 404))
  end

  products = Product.where(id: data['positions'].map { it['id'].to_i }.uniq)
  products_hash = {}
  products.each { |p| products_hash[p.id.to_i] = p }

  positions = []

  data['positions'].each do |position|
    id = position['id'].to_i
    quantity = position['quantity'].to_i
    product = products_hash[id]

    price = BigDecimal(position['price'])

    discounts = []
    if user.template.discount > 0
      discounts << PercentDiscount.new(user.template.discount)
    end
    if product&.type == 'discount'
      discounts << PercentDiscount.new(product.value)
    end
    if product&.type == 'noloyalty'
      discounts = []
    end
    current_price = price
    discounts.each do |discount|
      current_price = discount.call(current_price)
    end

    cashbacks = []
    if user.template.cashback > 0
      cashbacks << PercentCashback.new(user.template.cashback)
    end
    if product&.type == 'increased_cashback'
      cashbacks << PercentCashback.new(product.value)
    end
    if product&.type == 'noloyalty'
      cashbacks = []
    end
    cashback_value = BigDecimal(0)
    cashbacks.each do |cashback|
      cashback_value += cashback.call(current_price)
    end

    positions << {
      'response' => {
        'id' => position['id'],
        'price' => position['price'],
        'quantity' => position['quantity'],
        'type' => product&.type,
        'value' => product&.value,
        'description' => product&.name,
        'discount_percent' => (100 - current_price / price * 100).to_s('F'),
        'discount_value' => (price - current_price).to_s('F'),
        'total_discount_value' => ((price - current_price) * quantity).to_s('F')
      },
      'data' => {
        'type' => product&.type,
        'price' => price,
        'current_price' => current_price,
        'total_price' => price * quantity,
        'total_current_price' => current_price * quantity,

        'discount_value' => price - current_price,
        'total_discount_value' => (price - current_price) * quantity,
        'discount_percent' =>  100 - current_price / price * 100,

        'cashback_value' => cashback_value,
        'total_cashback_value' => cashback_value * quantity,
        'cashback_percent' => cashback_value / current_price * 100
      }
    }
  end

  total = BigDecimal(0)
  current_total = BigDecimal(0)
  cashback_percent = BigDecimal(0)
  cashback_value = BigDecimal(0)
  discount_percent = BigDecimal(0)
  discount_value = BigDecimal(0)

  positions.each do |position|
    total += position.dig('data', 'total_price')
    current_total += position.dig('data', 'total_current_price')
    cashback_value += position.dig('data', 'total_cashback_value')
    discount_value += position.dig('data', 'total_discount_value')
  end
  discount_percent = (discount_value / total * 100).round(2)
  cashback_percent = (cashback_value / current_total * 100).round(2)

  not_allowed = positions.sum { it.dig('data', 'type') == 'noloyalty' ? it.dig('data', 'total_current_price') : 0 }
  allowed_write_off = current_total - not_allowed
  allowed_write_off = allowed_write_off > user.bonus ? user.bonus : allowed_write_off

  operation = Operation.new(
    user_id: user.id,
    cashback: cashback_value,
    cashback_percent: cashback_percent,
    discount: discount_value,
    discount_percent: discount_percent,
    write_off: nil,
    check_summ: current_total,
    done: false,
    allowed_write_off: allowed_write_off
  ).save(raise_on_failure: true)

  content_type :json
  {
    'status' => 'OK',
    'user' => {
      'id' => user.id,
      'template' => user.template_id,
      'name' => user.name,
      'bonus' => user.bonus.to_s('F')
    },
    'operation_id' => operation.id,
    'check_summ' => current_total.to_s('F'),
    'bonus' => {
      'balance' => user.bonus.to_s('F'),
      'allowed_write_off' => operation.allowed_write_off.to_s('F'),
      'percent' => cashback_percent.to_s('F'),
      'value' => cashback_value.to_s('F')
    },
    'discount' => {
      'percent' => discount_percent.to_s('F'),
      'value' => discount_value.to_s('F')
    },
    'positions' => positions.map { it['response'] }
  }.to_json
end

post '/submit' do
  content_type :json
  data = JSON.parse(request.body.read)
  operation = Operation.with_pk(data['operation_id'])
  if operation.nil?
    halt(*json_error("Operation id=#{data['operation_id']} not found", code: 404))
  end
  if data['user_id'] != operation.user_id
    halt(*json_error("Operation id=#{data['operation_id']} forbidden submit", code: 403))
  end

  write_off = BigDecimal(data['write_off'])

  err = nil

  # SQLite not support FOR UPDATE and this is done using the transaction isolation level
  Operation.db.transaction(mode: :immediate) do
    user = User.for_update.with_pk(operation.user_id)
    operation = Operation.for_update.with_pk(operation.id)
    if operation.done
      err = json_error("Operation id=#{data['operation_id']} already done", code: 409)
      raise Sequel::Rollback
    end
    if write_off > operation.check_summ
      err = json_error(
        "Operation id=#{data['operation_id']} not allowed because the amount " \
        "to be debited exceeds the amount of the receipt",
        code: 403
      )
      raise Sequel::Rollback
    end
    if write_off > user.bonus
      err = json_error(
        "Operation id=#{data['operation_id']} not allowed because the amount " \
        "to be debited exceeds the user's bonuses",
        code: 403
      )
      raise Sequel::Rollback
    end
    operation.done = true
    operation.write_off = write_off
    operation.save
    user.bonus = user.bonus - write_off
    user.save
  end

  halt(*err) if err

  {
    'status' => 'OK',
    'message' => 'SUCCESS',
    'operation' => {
      'user_id' => operation.user_id,
      'cashback' => operation.cashback.to_s('F'),
      'cashback_percent' => operation.cashback_percent.to_s('F'),
      'discount' => operation.discount.to_s('F'),
      'discount_percent' => operation.discount_percent.to_s('F'),
      'write_off' => operation.write_off.to_s('F'),
      'amount_payable' => (operation.check_summ - operation.write_off).to_s('F')
    }
  }.to_json
end

def json_error(message, code: 400)
  [
    code,
    {
      'status' => 'ERROR',
      'message' => message
    }.to_json
  ]
end

class PercentDiscount
  def initialize(percent)
    @percent = BigDecimal(percent)
  end

  def call(price)
    BigDecimal(price) * (100 - @percent) / 100
  end
end

class PercentCashback
  def initialize(percent)
    @percent = BigDecimal(percent)
  end

  def call(price)
    BigDecimal(price) * @percent / 100
  end
end
