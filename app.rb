# frozen_string_literal: true

ENV['RACK_ENV'] ||= 'development'

require 'sinatra'
require_relative 'db'

get '/' do
  'Hello'
end
