# curl Testing Cheatsheet — API Endpoints

Use these commands to test your servlets as you build them.
Run from terminal while Tomcat is running on :8080.

## Auth

```bash
# Login (save session cookie to file)
curl -v -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}' \
  -c cookies.txt

# Check who's logged in
curl -b cookies.txt http://localhost:8080/api/auth/me

# Logout
curl -X POST -b cookies.txt http://localhost:8080/api/auth/logout

# Test without login (should get 401)
curl -v http://localhost:8080/api/customers
```

## Customers

```bash
# List all
curl -b cookies.txt http://localhost:8080/api/customers

# Search
curl -b cookies.txt "http://localhost:8080/api/customers?q=Ahmed"

# Get by ID
curl -b cookies.txt http://localhost:8080/api/customers/1

# Create
curl -X POST -b cookies.txt http://localhost:8080/api/customers \
  -H "Content-Type: application/json" \
  -d '{"name":"Sara Ali","address":"Alexandria","birthdate":"2000-01-15"}'

# Update
curl -X PUT -b cookies.txt http://localhost:8080/api/customers/1 \
  -H "Content-Type: application/json" \
  -d '{"name":"Ahmed Ali Updated","address":"New Cairo"}'
```

## Rate Plans

```bash
# List all
curl -b cookies.txt http://localhost:8080/api/rateplans

# Create
curl -X POST -b cookies.txt http://localhost:8080/api/rateplans \
  -H "Content-Type: application/json" \
  -d '{"name":"Gold","rorData":0.03,"rorVoice":0.08,"rorSms":0.01,"price":200}'
```

## Service Packages

```bash
# List all
curl -b cookies.txt http://localhost:8080/api/service-packages

# Create
curl -X POST -b cookies.txt http://localhost:8080/api/service-packages \
  -H "Content-Type: application/json" \
  -d '{"name":"Data Plus","type":"data","amount":10000,"priority":1}'
```

## Contracts

```bash
# List all
curl -b cookies.txt http://localhost:8080/api/contracts

# Create
curl -X POST -b cookies.txt http://localhost:8080/api/contracts \
  -H "Content-Type: application/json" \
  -d '{"customerId":1,"rateplanId":1,"msisdn":"201000000003","creditLimit":300}'
```

## Bills & Invoices

```bash
# Get bills for a contract
curl -b cookies.txt "http://localhost:8080/api/bills?contract_id=1"

# Download invoice PDF
curl -b cookies.txt http://localhost:8080/api/invoices/1/pdf -o invoice.pdf
```

## curl Flag Reference
```
-v          Verbose (show headers — useful for debugging)
-X POST     Set HTTP method
-H "..."    Set header
-d '{...}'  Request body (automatically sets POST if no -X)
-b file     Send cookies from file
-c file     Save response cookies to file
-o file     Save response body to file
```
