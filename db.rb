# frozen_string_literal: true

require 'sequel'

if ENV['RACK_ENV'] == 'development'
  dbfile = 'test.db'
  raise "'#{dbfile}' sqlite file not found" unless File.exist?(File.join(__dir__, dbfile))
  DB = Sequel.sqlite(dbfile)
elsif ENV['RACK_ENV'] == 'test'
  DB = Sequel.sqlite # In-memory DB
  DB.run(<<~SQL)
    CREATE TABLE "templates"
    (
     id INTEGER not null
       constraint template_pk
         primary key autoincrement,
     name varchar(255) not null,
     discount int not null,
     cashback int not null
    );

    CREATE TABLE "users"
    (
      id INTEGER not null
        constraint user_pk
          primary key autoincrement,
      template_id INT not null
        constraint template_id
          references "templates",
      name varchar(255) not null,
      bonus numeric
    );

    CREATE TABLE "products"
    (
      id INTEGER not null
        constraint table_name_pk
          primary key autoincrement,
      name varchar(255) not null,
      type varchar(255),
      value varchar(255)
    );

    CREATE TABLE "operations"
    (
      id INTEGER not null
        constraint operation_pk
          primary key autoincrement,
      user_id INT not null
        references "users",
      cashback numeric not null,
      cashback_percent numeric not null,
      discount numeric not null,
      discount_percent numeric not null,
      write_off numeric,
      check_summ numeric not null,
      done boolean,
      allowed_write_off numeric
    );
  SQL
else
  raise "Database not setup for '#{ENV['RACK_ENV']}' environment"
end

DB.loggers << Logger.new($stdout) if ENV['RACK_ENV'] == 'development'

class User < Sequel::Model(DB[:users])
  many_to_one :template
  one_to_many :operation
end

class Product < Sequel::Model(DB[:products])
end

class Template < Sequel::Model(DB[:templates])
  one_to_many :user
end

class Operation < Sequel::Model(DB[:operations])
  many_to_one :user
end
