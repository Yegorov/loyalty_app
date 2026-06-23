# frozen_string_literal: true

ENV['RACK_ENV'] ||= 'development'

require 'sinatra'
require_relative 'db'

get '/' do
  'Hello'
end

post '/operation' do
  data = JSON.parse(request.body.read)

  user = User.eager(:template).with_pk(data['user_id'])
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
    cashback_value = 0
    cashbacks.each do |cashback|
      cashback_value += cashback.call(current_price)
    end

    positions << {
      'response' => {
        'type' => product&.type,
        'value' => product&.value,
        'description' => product&.name,
        'discount_percent' => (100 - current_price / price * 100).to_s('F'),
        'discount_value' => (price - current_price).to_s('F'),
        'total_discount_value' => ((price - current_price) * quantity).to_s('F')
      },
      'data' => {
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

  total = 0
  current_total = 0
  cashback_percent = 0
  cashback_value = 0
  discount_percent = 0
  discount_value = 0

  positions.each do |position|
    total += position.dig('data', 'total_price')
    current_total += position.dig('data', 'total_current_price')
    cashback_value += position.dig('data', 'total_cashback_value')
    discount_value += position.dig('data', 'total_discount_value')
  end
  discount_percent = (discount_value / total * 100).round(2)
  cashback_percent = (cashback_value / current_total * 100).round(2)

  operation = Operation.new(
    user_id: user.id,
    cashback: cashback_value,
    cashback_percent: cashback_percent,
    discount: discount_value,
    discount_percent: discount_percent,
    write_off: nil,
    check_summ: current_total,
    done: false,
    allowed_write_off: current_total > user.bonus ? user.bonus : current_total
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
      'write_off' => user.bonus.to_s('F'),
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
  operation = Operation.eager(:user).with_pk(data['operation_id'])
  if operation.nil?
    halt(404, json_error("Operation id=#{data['operation_id']} not found"))
  end
  if data.dig('user', 'id') != operation.user.id
    halt(403, json_error("Operation id=#{data['operation_id']} forbidden submit"))
  end

  write_off = BigDecimal(data['write_off'])

  err = nil

  # SQLite not support FOR UPDATE and this is done using the transaction isolation level
  Operation.db.transaction(mode: :immediate) do
    user = User.for_update.with_pk(operation.user_id)
    operation = Operation.for_update.with_pk(operation.id)
    if write_off > operation.check_summ
      err = json_error(
        "Operation id=#{data['operation_id']} not allowed because the amount " \
        "to be debited exceeds the amount of the receipt"
      )
      raise Sequel::Rollback
    end
    if write_off > operation.user.bonus
      err = json_error(
        "Operation id=#{data['operation_id']} not allowed because the amount " \
        "to be debited exceeds the user's bonuses"
      )
      raise Sequel::Rollback
    end
    operation.done = true
    operation.write_off = write_off
    operation.save
    user.bonus = user.bonus - write_off
    user.save
  end

  halt(403, err) if err

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

def json_error(message)
  {
    'status' => 'ERROR',
    'message' => message
  }.to_json
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
