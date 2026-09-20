// Maintain / query the NoSQL database and show configuration
db = db.getSiblingDB('catalog');

print('--- Mongo server version: ' + db.version());
print('--- Products tagged "network", cheapest first:');
db.products.find({ tags: 'network' }).sort({ price: 1 }).forEach(p => printjson(p));

print('--- Configured indexes on products:');
printjson(db.products.getIndexes());

print('--- Schema validation is enforced (bad insert must be rejected):');
try {
  db.products.insertOne({ sku: 123 });      // wrong type + missing fields
  print('!! ERROR: invalid document was accepted');
} catch (e) {
  print('OK, rejected as expected: ' + e.message);
}
