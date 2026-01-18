import 'package:flutter/material.dart';
import 'package:offline_first/offline_first.dart';
import 'package:uuid/uuid.dart';

import 'models/product.dart';
import 'adapters/product_remote_adapter.dart';
import 'backend/mock_backend.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline First Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late OfflineStore store;
  late MockBackend backend;
  bool isInitialized = false;
  bool isOnline = true;
  List<Product> products = [];
  List<Operation> pendingOperations = [];

  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _initializeStore();
  }

  Future<void> _initializeStore() async {
    backend = MockBackend();

    final storage = InMemoryStorageAdapter();
    final adapters = {
      'product': ProductRemoteAdapter(backend),
    };

    store = await OfflineStore.init(
      storage: storage,
      adapters: adapters,
      conflictResolver: LastWriteWinsResolver(),
      config: OfflineStoreConfig(
        deviceId: _uuid.v4(),
        syncConfig: const SyncConfig(
          enableOperationReduction: true,
          maxRetries: 3,
        ),
      ),
    );

    // Listen to sync status
    store.syncStatusStream.listen((event) {
      if (mounted) {
        setState(() {});
      }
    });

    // Load initial products from backend
    for (final product in backend.initialProducts.values) {
      await store.save('product', product.id, product.toMap());
    }

    await _refreshData();

    setState(() {
      isInitialized = true;
    });
  }

  Future<void> _refreshData() async {
    final data = await store.getAll('product');
    final ops = await store.getPendingOperations();

    setState(() {
      products = data.map((m) => ProductOfflineExtension.fromMap(m)).toList();
      pendingOperations = ops;
    });
  }

  Future<void> _addProduct() async {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final stockController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Product'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: priceController,
              decoration: const InputDecoration(labelText: 'Price'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: stockController,
              decoration: const InputDecoration(labelText: 'Stock'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final product = Product(
                id: _uuid.v4(),
                name: nameController.text,
                price: double.tryParse(priceController.text) ?? 0,
                stock: int.tryParse(stockController.text) ?? 0,
              );

              await store.save('product', product.id, product.toMap(), isNew: true);
              await _refreshData();

              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _editProduct(Product product) async {
    final nameController = TextEditingController(text: product.name);
    final priceController = TextEditingController(text: product.price.toString());
    final stockController = TextEditingController(text: product.stock.toString());

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Product'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: priceController,
              decoration: const InputDecoration(labelText: 'Price'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: stockController,
              decoration: const InputDecoration(labelText: 'Stock'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final updated = Product(
                id: product.id,
                name: nameController.text,
                price: double.tryParse(priceController.text) ?? product.price,
                stock: int.tryParse(stockController.text) ?? product.stock,
              );

              await store.save('product', updated.id, updated.toMap());
              await _refreshData();

              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteProduct(Product product) async {
    await store.delete('product', product.id);
    await _refreshData();
  }

  Future<void> _sync() async {
    backend.isOnline = isOnline;

    try {
      await store.sync();
      await _refreshData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync completed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    }
  }

  void _toggleOnline() {
    setState(() {
      isOnline = !isOnline;
      backend.isOnline = isOnline;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline First Demo'),
        actions: [
          IconButton(
            icon: Icon(isOnline ? Icons.cloud : Icons.cloud_off),
            onPressed: _toggleOnline,
            tooltip: isOnline ? 'Go Offline' : 'Go Online',
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: store.isSyncing ? null : _sync,
            tooltip: 'Sync',
          ),
        ],
      ),
      body: Row(
        children: [
          // Products list
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.blue.shade50,
                  child: Row(
                    children: [
                      const Text(
                        'Products',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Chip(
                        label: Text('${products.length} items'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: ListTile(
                          title: Text(product.name),
                          subtitle: Text(
                            'Price: \$${product.price.toStringAsFixed(2)} | Stock: ${product.stock}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _editProduct(product),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () => _deleteProduct(product),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Operations queue
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.orange.shade50,
                  child: Row(
                    children: [
                      const Text(
                        'Pending Operations',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text('${pendingOperations.length}'),
                        backgroundColor: pendingOperations.isEmpty
                            ? Colors.green
                            : Colors.orange,
                      ),
                    ],
                  ),
                ),
                if (store.isSyncing)
                  const LinearProgressIndicator(),
                Expanded(
                  child: ListView.builder(
                    itemCount: pendingOperations.length,
                    itemBuilder: (context, index) {
                      final op = pendingOperations[index];
                      return Card(
                        margin: const EdgeInsets.all(8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                op.operationType.name.toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text('Entity: ${op.entityType}'),
                              Text('ID: ${op.entityId.length > 8 ? "${op.entityId.substring(0, 8)}..." : op.entityId}'),
                              Text('Status: ${op.status.name}'),
                              if (op.retryCount > 0)
                                Text('Retries: ${op.retryCount}'),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addProduct,
        child: const Icon(Icons.add),
      ),
    );
  }
}
