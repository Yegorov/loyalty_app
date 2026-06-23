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
    payload = {
      'user_id' => 3,
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
  end

  def test_operation_with_noloyalty_product
    seed_db
    payload = {
      'user_id' => 2,
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
  end

  def test_submit_simple
    seed_db
    payload = {

    }
    post '/submit', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    assert last_response.ok?
    response = JSON.parse(last_response.body)
    assert_equal 'OK', response['status']
  end
end
