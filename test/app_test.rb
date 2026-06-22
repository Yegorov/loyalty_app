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
end
