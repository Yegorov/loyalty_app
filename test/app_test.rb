require 'helper'

class AppTest < BaseTest
  def test_home
    get '/'
    assert last_response.ok?
    assert_equal 'Hello', last_response.body
  end

  def test_seed_db
    assert_equal 0, DB['SELECT COUNT(1) AS count FROM templates'].to_a.first[:count]
    assert_equal 0, DB['SELECT COUNT(1) AS count FROM users'].to_a.first[:count]
    assert_equal 0, DB['SELECT COUNT(1) AS count FROM products'].to_a.first[:count]
    assert_equal 0, DB['SELECT COUNT(1) AS count FROM operations'].to_a.first[:count]
    seed_db
    assert_equal 3, DB['SELECT COUNT(1) AS count FROM templates'].to_a.first[:count]
    assert_equal 3, DB['SELECT COUNT(1) AS count FROM users'].to_a.first[:count]
    assert_equal 3, DB['SELECT COUNT(1) AS count FROM products'].to_a.first[:count]
    assert_equal 0, DB['SELECT COUNT(1) AS count FROM operations'].to_a.first[:count]
  end

  def test_operation_with_unknown_product
    seed_db
    user = User.with_pk(3)
    payload = {
      'user_id' => user.id,
      'positions' => [
        { "id" => 2, "price" => 200, "quantity" => 3 },
        { "id" => 1002, "price" => 350, "quantity" => 2 }
      ]
    }
    post '/operation', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    assert last_response.ok?
    response = JSON.parse(last_response.body)
    assert_equal 'OK', response['status']
    assert_predicate response['operation_id'], :positive?
    assert_equal 3, response.dig('user', 'id')
    assert_equal 'Женя', response.dig('user', 'name')
    assert_equal '1105.0', response['check_summ']
    assert_equal '4.62', response.dig('bonus', 'percent')
    assert_equal '51.0', response.dig('bonus', 'value')
    assert_equal '15.0', response.dig('discount', 'percent')
    assert_equal '195.0', response.dig('discount', 'value')
    response.dig('positions', 0).then do |p|
      assert_equal 'increased_cashback', p['type']
      assert_equal '10', p['value']
      assert_equal 'Молоко', p['description']
      assert_equal '15.0', p['discount_percent']
      assert_equal '30.0', p['discount_value']
      assert_equal '90.0', p['total_discount_value']
    end
    response.dig('positions', 1).then do |p|
      assert_nil p['type']
      assert_nil p['value']
      assert_nil p['description']
      assert_equal '15.0', p['discount_percent']
      assert_equal '52.5', p['discount_value']
      assert_equal '105.0', p['total_discount_value']
    end
    Operation.with_pk(response['operation_id']).then do |operation|
      assert_equal user.id, operation.user_id
      assert_in_delta 51, operation.cashback
      assert_in_delta 4.62, operation.cashback_percent
      assert_in_delta 195, operation.discount
      assert_in_delta 15, operation.discount_percent
      assert_nil operation.write_off
      assert_in_delta 1105, operation.check_summ
      refute operation.done
      assert_in_delta 1105, operation.allowed_write_off
    end
  end

  def test_operation_with_noloyalty_product
    seed_db
    user = User.with_pk(2)
    payload = {
      'user_id' => user.id,
      'positions' => [
        { "id" => 2, "price" => 100, "quantity" => 3 },
        { "id" => 3, "price" => 200, "quantity" => 2 },
        { "id" => 4, "price" => 50, "quantity" => 1 },
      ]
    }
    post '/operation', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    assert last_response.ok?
    response = JSON.parse(last_response.body)
    assert_equal 'OK', response['status']
    assert_predicate response['operation_id'], :positive?
    assert_equal '658.0', response['check_summ']
    assert_equal '8.95', response.dig('bonus', 'percent')
    assert_equal '58.9', response.dig('bonus', 'value')
    assert_equal '12.27', response.dig('discount', 'percent')
    assert_equal '92.0', response.dig('discount', 'value')
    response.dig('positions', 0).then do |p|
      assert_equal 'increased_cashback', p['type']
      assert_equal '5.0', p['discount_percent']
      assert_equal '5.0', p['discount_value']
      assert_equal '15.0', p['total_discount_value']
    end
    response.dig('positions', 1).then do |p|
      assert_equal 'discount', p['type']
      assert_equal '19.25', p['discount_percent']
      assert_equal '38.5', p['discount_value']
      assert_equal '77.0', p['total_discount_value']
    end
    response.dig('positions', 2).then do |p|
      assert_equal 'noloyalty', p['type']
      assert_equal '0.0', p['discount_percent']
      assert_equal '0.0', p['discount_value']
      assert_equal '0.0', p['total_discount_value']
    end
    Operation.with_pk(response['operation_id']).then do |operation|
      assert_equal user.id, operation.user_id
      assert_in_delta 58.9, operation.cashback
      assert_in_delta 8.95, operation.cashback_percent
      assert_in_delta 92, operation.discount
      assert_in_delta 12.27, operation.discount_percent
      assert_nil operation.write_off
      assert_in_delta 658, operation.check_summ
      refute operation.done
      assert_in_delta 658, operation.allowed_write_off
    end
  end

  def test_submit_success
    seed_db
    user = User.with_pk(1)
    operation = Operation.new(
      user_id: user.id,
      cashback: BigDecimal(18),
      cashback_percent: BigDecimal(2),
      discount: BigDecimal(100),
      discount_percent: BigDecimal(10),
      write_off: nil,
      check_summ: BigDecimal(900),
      done: false,
      allowed_write_off: BigDecimal(900)
    ).save(raise_on_failure: true)
    payload = {
      'user' => {
        'id' => user.id,
        'template_id' => user.template_id,
        'name' => user.name,
        'bonus' => user.bonus.to_s('F')
      },
      'operation_id' => operation.id,
      'write_off' => 300
    }
    post '/submit', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    assert last_response.ok?
    response = JSON.parse(last_response.body)
    assert_equal 'OK', response['status']
    assert_equal 'SUCCESS', response['message']
    assert_equal user.id, response.dig('operation', 'user_id')
    assert_equal '18.0', response.dig('operation', 'cashback')
    assert_equal '2.0', response.dig('operation', 'cashback_percent')
    assert_equal '100.0', response.dig('operation', 'discount')
    assert_equal '10.0', response.dig('operation', 'discount_percent')
    assert_equal '300.0', response.dig('operation', 'write_off')
    assert_equal '600.0', response.dig('operation', 'amount_payable')
    operation.reload
    assert_equal user.id, operation.user_id
    assert_in_delta 18, operation.cashback
    assert_in_delta 2, operation.cashback_percent
    assert_in_delta 100, operation.discount
    assert_in_delta 10, operation.discount_percent
    assert_in_delta 300, operation.write_off
    assert_in_delta 900, operation.check_summ
    assert operation.done
    assert_in_delta 900, operation.allowed_write_off
    user.reload
    assert_in_delta 9700, user.bonus
  end

  def test_submit_not_found_operation
    seed_db
    user = User.with_pk(1)
    payload = {
      'user' => {
        'id' => user.id,
        'template_id' => user.template_id,
        'name' => user.name,
        'bonus' => user.bonus.to_s('F')
      },
      'operation_id' => 10000001,
      'write_off' => 300
    }
    post '/submit', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    refute last_response.ok?
    assert_equal 404, last_response.status
    response = JSON.parse(last_response.body)
    assert_equal 'ERROR', response['status']
    assert_equal 'Operation id=10000001 not found', response['message']
  end

  def test_submit_forbidden
    seed_db
    user = User.with_pk(1)
    user2 = User.with_pk(2)
    operation = Operation.new(
      user_id: user.id,
      cashback: BigDecimal(18),
      cashback_percent: BigDecimal(2),
      discount: BigDecimal(100),
      discount_percent: BigDecimal(10),
      write_off: nil,
      check_summ: BigDecimal(900),
      done: false,
      allowed_write_off: BigDecimal(900)
    ).save(raise_on_failure: true)
    payload = {
      'user' => {
        'id' => user2.id,
        'template_id' => user2.template_id,
        'name' => user2.name,
        'bonus' => user2.bonus.to_s('F')
      },
      'operation_id' => operation.id,
      'write_off' => 300
    }
    post '/submit', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    refute last_response.ok?
    assert_equal 403, last_response.status
    response = JSON.parse(last_response.body)
    assert_equal 'ERROR', response['status']
    assert_equal 'Operation id=1 forbidden submit', response['message']
    operation.reload
    assert_equal user.id, operation.user_id
    assert_in_delta 18, operation.cashback
    assert_in_delta 2, operation.cashback_percent
    assert_in_delta 100, operation.discount
    assert_in_delta 10, operation.discount_percent
    assert_nil operation.write_off
    assert_in_delta 900, operation.check_summ
    refute operation.done
    assert_in_delta 900, operation.allowed_write_off
    user.reload
    assert_in_delta 10000, user.bonus
  end

  def test_submit_with_write_off_exceeds_check_summ
    seed_db
    user = User.with_pk(1)
    operation = Operation.new(
      user_id: user.id,
      cashback: BigDecimal(18),
      cashback_percent: BigDecimal(2),
      discount: BigDecimal(100),
      discount_percent: BigDecimal(10),
      write_off: nil,
      check_summ: BigDecimal(900),
      done: false,
      allowed_write_off: BigDecimal(900)
    ).save(raise_on_failure: true)
    payload = {
      'user' => {
        'id' => user.id,
        'template_id' => user.template_id,
        'name' => user.name,
        'bonus' => user.bonus.to_s('F')
      },
      'operation_id' => operation.id,
      'write_off' => 1000
    }
    post '/submit', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    refute last_response.ok?
    assert_equal 403, last_response.status
    response = JSON.parse(last_response.body)
    assert_equal 'ERROR', response['status']
    assert_equal(
      'Operation id=1 not allowed because the amount to be debited exceeds the amount of the receipt',
      response['message']
    )
    operation.reload
    assert_equal user.id, operation.user_id
    assert_in_delta 18, operation.cashback
    assert_in_delta 2, operation.cashback_percent
    assert_in_delta 100, operation.discount
    assert_in_delta 10, operation.discount_percent
    assert_nil operation.write_off
    assert_in_delta 900, operation.check_summ
    refute operation.done
    assert_in_delta 900, operation.allowed_write_off
    user.reload
    assert_in_delta 10000, user.bonus
  end

  def test_submit_with_write_off_exceeds_user_bonus
    seed_db
    user = User.with_pk(1)
    operation = Operation.new(
      user_id: user.id,
      cashback: BigDecimal(1800),
      cashback_percent: BigDecimal(2),
      discount: BigDecimal(10000),
      discount_percent: BigDecimal(10),
      write_off: nil,
      check_summ: BigDecimal(90000),
      done: false,
      allowed_write_off: BigDecimal(10000)
    ).save(raise_on_failure: true)
    payload = {
      'user' => {
        'id' => user.id,
        'template_id' => user.template_id,
        'name' => user.name,
        'bonus' => user.bonus.to_s('F')
      },
      'operation_id' => operation.id,
      'write_off' => 10001
    }
    post '/submit', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    refute last_response.ok?
    assert_equal 403, last_response.status
    response = JSON.parse(last_response.body)
    assert_equal 'ERROR', response['status']
    assert_equal(
      "Operation id=1 not allowed because the amount to be debited exceeds the user's bonuses",
      response['message']
    )
    operation.reload
    assert_equal user.id, operation.user_id
    assert_in_delta 1800, operation.cashback
    assert_in_delta 2, operation.cashback_percent
    assert_in_delta 10000, operation.discount
    assert_in_delta 10, operation.discount_percent
    assert_nil operation.write_off
    assert_in_delta 90000, operation.check_summ
    refute operation.done
    assert_in_delta 10000, operation.allowed_write_off
    user.reload
    assert_in_delta 10000, user.bonus
  end
end
