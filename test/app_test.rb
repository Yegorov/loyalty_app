require 'helper'

class AppTest < Minitest::Test
  def test_home
    get '/'
    assert last_response.ok?
    assert_equal 'Hello', last_response.body
  end
end
