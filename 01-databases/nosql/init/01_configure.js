// Configure & maintain a NoSQL database:
// validated collection, unique + secondary indexes, seed data, app user.
db = db.getSiblingDB('catalog');

db.createCollection('products', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['sku', 'name', 'price'],
      properties: {
        sku:   { bsonType: 'string' },
        name:  { bsonType: 'string' },
        price: { bsonType: 'double', minimum: 0 },
        tags:  { bsonType: 'array' }
      }
    }
  }
});

db.products.createIndex({ sku: 1 }, { unique: true });
db.products.createIndex({ tags: 1 });

db.products.insertMany([
  { sku: 'A-100', name: 'Router X1',     price: Double(199.99), tags: ['network', 'hardware'] },
  { sku: 'A-101', name: 'Switch S8',     price: Double(349.50), tags: ['network', 'hardware'] },
  { sku: 'B-200', name: 'Support Plan',  price: Double(49.00),  tags: ['service'] }
]);

db.createUser({
  user: 'catalog_app',
  pwd:  'app_pass',
  roles: [{ role: 'readWrite', db: 'catalog' }]
});
