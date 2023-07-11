//001 - Load Customer Data
MATCH (n) DETACH DELETE n;
CALL apoc.schema.assert({},{});
// Create customers
LOAD CSV WITH HEADERS FROM "https://emil-neo4j-bucket.s3.ap-southeast-2.amazonaws.com/customers.csv" AS row
MERGE (c:Customer {customerID: row.customerID})
ON CREATE SET c.companyName=row.companyName, c.fax=row.fax, c.phone=row.phone
ON MATCH SET c.companyName=row.companyName, c.fax=row.fax, c.phone=row.phone;

//002 - Load Order and connect to customer
// Create Orders
LOAD CSV WITH HEADERS FROM "https://emil-neo4j-bucket.s3.ap-southeast-2.amazonaws.com/orders.csv" AS row
MERGE (o:Order {orderID: toInteger(row.orderID)}) ON CREATE SET o.shipName =  row.shipName;

// Relate customers to orders
LOAD CSV WITH HEADERS FROM "https://emil-neo4j-bucket.s3.ap-southeast-2.amazonaws.com/orders.csv" AS row
MATCH (o:Order {orderID: toInteger(row.orderID)})
MATCH (customer:Customer {customerID: row.customerID})
MERGE (customer)-[:PURCHASED]->(o);

//003 - Load and connect the remaining data
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/adam-cowley/northwind-neo4j/master/data/products.csv" AS row
CREATE (:Product {productName: row.productName, productID: row.productID, unitPrice: toFloat(row.UnitPrice)});

// Create suppliers
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/adam-cowley/northwind-neo4j/master/data/suppliers.csv" AS row
CREATE (:Supplier {companyName: row.companyName, supplierID: row.supplierID});

// Create employees
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/adam-cowley/northwind-neo4j/master/data/employees.csv" AS row
CREATE (:Employee {employeeID:row.employeeID,  firstName: row.firstName, lastName: row.lastName, title: row.title});

// Create categories
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/adam-cowley/northwind-neo4j/master/data/categories.csv" AS row
CREATE (:Category {categoryID: row.categoryID, categoryName: row.categoryName, description: row.description});

// Relate orders to products
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/adam-cowley/northwind-neo4j/master/data/order-details.csv" AS row
MATCH (o:Order {orderID: row.orderID})
MATCH (product:Product {productID: row.productID})
MERGE (o)-[pu:PRODUCT]->(product)
ON CREATE SET pu.unitPrice = toFloat(row.unitPrice), pu.quantity = toFloat(row.quantity);

// Relate Orders to Employees
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/adam-cowley/northwind-neo4j/master/data/orders.csv" AS row
MATCH (o:Order {orderID: toInteger(row.orderID)})
MATCH (employee:Employee {employeeID: row.employeeID})
MERGE (employee)-[:SOLD]->(o);

// Relate Products to suppliers
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/adam-cowley/northwind-neo4j/master/data/products.csv" AS row
MATCH (product:Product {productID: row.productID})
MATCH (supplier:Supplier {supplierID: row.supplierID})
MERGE (supplier)-[:SUPPLIES]->(product);

// Relate Products to Categories
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/adam-cowley/northwind-neo4j/master/data/products.csv" AS row
MATCH (product:Product {productID: row.productID})
MATCH (category:Category {categoryID: row.categoryID})
MERGE (product)-[:PART_OF]->(category);

// Relate employees to managers
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/adam-cowley/northwind-neo4j/master/data/employees.csv" AS row
MATCH (employee:Employee {employeeID: row.employeeID})
MATCH (manager:Employee {employeeID: row.reportsTo})
MERGE (employee)-[:REPORTS_TO]->(manager);

// Add unit price
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/adam-cowley/northwind-neo4j/master/data/order-details.csv" AS row
MATCH (o:Order {orderID: toInteger(row.orderID)})
MATCH (product:Product {productID: row.productID})
MERGE (o)-[pu:PRODUCT]->(product)
ON CREATE SET pu.unitPrice = toFloat(row.unitPrice), pu.quantity = toFloat(row.quantity);

//004 - Additional Processing
CALL apoc.periodic.iterate(
'MATCH (c:Customer) RETURN c',
'MATCH (c)-[:PURCHASED]->(e:Order)
WITH e
ORDER BY e.orderID
WITH collect(e) AS events
WITH events, events[1..] as nextEvents
UNWIND range(0,size(nextEvents)-1,1) as index
WITH events[index] as first, nextEvents[index] as second, index
MERGE (first)-[:NEXT_ORDER{, relationshipSequence:index}]->(second)',{iterateList:false});

MATCH (n:Customer)
WHERE split(n.customerID,'')[0] IN ['A', 'B', 'C', 'D', 'E']
SET n:LoyalCustomer
;

MATCH (n:Customer)
WHERE n.customerID STARTS WITH "A"
SET n:VIPCustomer
;

// Get the total number of products the customer purchased
MATCH (c:Customer)-[:PURCHASED]->(o:Order)-[:PRODUCT]->(p:Product)
WITH c, count(p) as total_items

// Get the number of times the customer orders the product
MATCH (c)-[:PURCHASED]->(o:Order)-[:PRODUCT]->(p:Product)
WITH c, total_items, p, count(o)*1.0 as orders

// Derive the rating as the number of times the customer orders the products against the total number of orders
MERGE (c)-[rated:RATED]->(p)
ON CREATE SET rated.rating = orders/total_items
ON MATCH SET rated.rating = orders/total_items
WITH c.companyName as company, p.productName as product, orders, total_items, rated.rating as rating
ORDER BY total_items DESC
RETURN company, product, orders, total_items, rating
LIMIT 10
;

MATCH (c:Customer)-[r:RATED]->(p:Product)
WHERE r.rating>=0.2
MERGE (c)-[:HIGH_RATING]->(p)
;

MATCH (c:Customer)-[r:RATED]->(p:Product)
WHERE r.rating<0.02
MERGE (c)-[:LOW_RATING]->(p)
;