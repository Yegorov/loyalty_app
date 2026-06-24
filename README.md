## loyalty_app

### Setup
```
git clone git@github.com:Yegorov/loyalty_app.git
cd loyalty_app
bundle install
bin/test
# Download test.db and place in root folder
bin/run
```

### Examples
```
curl -X POST -H 'Content-Type: application/json' 'http://127.0.0.1:4567/operation' --data '{
  "user_id": 3,
  "positions": [
    { "id": 2, "price": 100, "quantity": 3 },
    { "id": 1002, "price": 500, "quantity": 2 }
  ]
}
' | jq

{
  "status": "OK",
  "user": {
    "id": 3,
    "template": 3,
    "name": "Женя",
    "bonus": "10000.0"
  },
  "operation_id": 2,
  "check_summ": "1105.0",
  "bonus": {
    "balance": "10000.0",
    "allowed_write_off": "1105.0",
    "percent": "2.31",
    "value": "25.5"
  },
  "discount": {
    "percent": "15.0",
    "value": "195.0"
  },
  "positions": [
    {
      "id": 2,
      "price": 100,
      "quantity": 3,
      "type": "increased_cashback",
      "value": "10",
      "description": "Молоко",
      "discount_percent": "15.0",
      "discount_value": "15.0",
      "total_discount_value": "45.0"
    },
    {
      "id": 1002,
      "price": 500,
      "quantity": 2,
      "type": null,
      "value": null,
      "description": null,
      "discount_percent": "15.0",
      "discount_value": "75.0",
      "total_discount_value": "150.0"
    }
  ]
}
```

```
curl -X POST -H 'Content-Type: application/json' 'http://127.0.0.1:4567/submit' --data '{
  "user_id": 3,
  "operation_id": 2,
  "write_off": 100
}
' | jq

{
  "status": "OK",
  "message": "SUCCESS",
  "operation": {
    "user_id": 3,
    "cashback": "25.5",
    "cashback_percent": "2.31",
    "discount": "195.0",
    "discount_percent": "15.0",
    "write_off": "100.0",
    "amount_payable": "1005.0"
  }
}
```
