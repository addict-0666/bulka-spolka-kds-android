import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Wymuszenie poziomej orientacji dla tabletu
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const BulkaKdsApp());
}

class BulkaKdsApp extends StatelessWidget {
  const BulkaKdsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bułka & Spółka - KDS Tablet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101216),
        cardColor: const Color(0xFF1B1E26),
        primaryColor: const Color(0xFFE56A18),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE56A18),
          secondary: Color(0xFFFFB300),
          surface: Color(0xFF1B1E26),
        ),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF151820),
          elevation: 2,
        ),
      ),
      home: const KdsScreen(),
    );
  }
}

enum OrderStatus {
  pendingPayment,
  paid,
  preparing,
  ready,
  completed,
  cancelled;

  static OrderStatus fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'PAID':
        return OrderStatus.paid;
      case 'PREPARING':
        return OrderStatus.preparing;
      case 'READY':
        return OrderStatus.ready;
      case 'COMPLETED':
        return OrderStatus.completed;
      case 'CANCELLED':
        return OrderStatus.cancelled;
      default:
        return OrderStatus.pendingPayment;
    }
  }

  String toApiString() {
    switch (this) {
      case OrderStatus.paid:
        return 'PAID';
      case OrderStatus.preparing:
        return 'PREPARING';
      case OrderStatus.ready:
        return 'READY';
      case OrderStatus.completed:
        return 'COMPLETED';
      case OrderStatus.cancelled:
        return 'CANCELLED';
      case OrderStatus.pendingPayment:
        return 'PENDING_PAYMENT';
    }
  }

  String get label {
    switch (this) {
      case OrderStatus.pendingPayment:
        return 'Oczekuje na wpłatę';
      case OrderStatus.paid:
        return 'NOWE ZAMÓWIENIE';
      case OrderStatus.preparing:
        return 'W PRZYGOTOWANIU';
      case OrderStatus.ready:
        return 'GOTOWE DO ODBIORU';
      case OrderStatus.completed:
        return 'WYDANE';
      case OrderStatus.cancelled:
        return 'ANULOWANE';
    }
  }

  Color get color {
    switch (this) {
      case OrderStatus.pendingPayment:
        return Colors.grey;
      case OrderStatus.paid:
        return const Color(0xFFE53935); // Czerwony - pilne!
      case OrderStatus.preparing:
        return const Color(0xFFFB8C00); // Pomarańczowy
      case OrderStatus.ready:
        return const Color(0xFF43A047); // Zielony
      case OrderStatus.completed:
        return const Color(0xFF546E7A); // Szaroniebieski
      case OrderStatus.cancelled:
        return const Color(0xFFD32F2F);
    }
  }
}

class OrderItemModel {
  final String title;
  final int quantity;
  final double price;
  final String? sauce;
  final String? meat;
  final List<String> extras;

  OrderItemModel({
    required this.title,
    required this.quantity,
    required this.price,
    this.sauce,
    this.meat,
    this.extras = const [],
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> json) {
    List<String> ext = [];
    if (json['extras'] is List) {
      ext = (json['extras'] as List).map((e) => e.toString()).toList();
    }
    return OrderItemModel(
      title: json['name'] ?? json['title'] ?? 'Danie',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      sauce: json['sauce']?.toString(),
      meat: json['meat']?.toString() ?? json['meatName']?.toString(),
      extras: ext,
    );
  }
}

class CustomerModel {
  final String name;
  final String phone;
  final String? email;
  final String? address;
  final String? notes;

  CustomerModel({
    required this.name,
    required this.phone,
    this.email,
    this.address,
    this.notes,
  });

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    return CustomerModel(
      name: json['name'] ?? 'Klient',
      phone: json['phone'] ?? '-',
      email: json['email'],
      address: json['address'],
      notes: json['notes'],
    );
  }
}

class OrderModel {
  final String orderId;
  final DateTime createdAt;
  final String deliveryType; // 'pickup' / 'delivery'
  final double totalAmount;
  final String paymentMethod;
  OrderStatus status;
  int? estimatedMinutes;
  DateTime? estimatedReadyAt;
  String? cancelReason;
  final CustomerModel customer;
  final List<OrderItemModel> items;

  OrderModel({
    required this.orderId,
    required this.createdAt,
    required this.deliveryType,
    required this.totalAmount,
    required this.paymentMethod,
    required this.status,
    this.estimatedMinutes,
    this.estimatedReadyAt,
    this.cancelReason,
    required this.customer,
    required this.items,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    List<OrderItemModel> itemsList = [];
    if (json['items'] is List) {
      itemsList = (json['items'] as List)
          .map((i) => OrderItemModel.fromJson(i as Map<String, dynamic>))
          .toList();
    }

    return OrderModel(
      orderId: json['orderId'] ?? 'ID',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      deliveryType: json['deliveryType'] ?? 'pickup',
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: json['paymentMethod'] ?? 'autopay',
      status: OrderStatus.fromString(json['status']?.toString()),
      estimatedMinutes: (json['estimatedMinutes'] as num?)?.toInt(),
      estimatedReadyAt: json['estimatedReadyAt'] != null
          ? DateTime.tryParse(json['estimatedReadyAt'])
          : null,
      cancelReason: json['cancelReason']?.toString(),
      customer: CustomerModel.fromJson(
        (json['customer'] as Map<String, dynamic>?) ?? {},
      ),
      items: itemsList,
    );
  }

  int get elapsedMinutes => DateTime.now().difference(createdAt).inMinutes;
}

class KdsScreen extends StatefulWidget {
  const KdsScreen({super.key});

  @override
  State<KdsScreen> createState() => _KdsScreenState();
}

class _KdsScreenState extends State<KdsScreen> {
  String _serverIp = '192.168.100.5';
  String _serverPort = '3000';
  bool _isConnected = false;
  bool _isLoading = false;
  String _errorMessage = '';
  List<OrderModel> _orders = [];
  Timer? _pollingTimer;
  Timer? _uiClockTimer;

  // Filtr: 'active', 'paid', 'preparing', 'ready', 'completed', 'cancelled'
  String _filter = 'active';

  @override
  void initState() {
    super.initState();
    _loadSettingsAndStart();
    _uiClockTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _uiClockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettingsAndStart() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _serverIp = prefs.getString('server_ip') ?? '192.168.100.5';
      _serverPort = prefs.getString('server_port') ?? '3000';
    });
    _fetchOrders();
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      _fetchOrders(silent: true);
    });
  }

  String get _baseUrl => 'http://$_serverIp:$_serverPort';

  Future<void> _fetchOrders({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
    }

    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/api/orders'))
          .timeout(const Duration(seconds: 3));

      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        final fetched = data.map((e) => OrderModel.fromJson(e)).toList();

        if (mounted) {
          setState(() {
            _orders = fetched;
            _isConnected = true;
            _isLoading = false;
            _errorMessage = '';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isConnected = false;
            _isLoading = false;
            _errorMessage = 'Błąd serwera: Kod ${res.statusCode}';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isLoading = false;
          _errorMessage = 'Brak połączenia z: $_baseUrl';
        });
      }
    }
  }

  Future<void> _updateOrderStatus({
    required OrderModel order,
    required OrderStatus nextStatus,
    int? estimatedMinutes,
    String? cancelReason,
  }) async {
    final prev = order.status;
    setState(() {
      order.status = nextStatus;
      if (estimatedMinutes != null) order.estimatedMinutes = estimatedMinutes;
      if (cancelReason != null) order.cancelReason = cancelReason;
    });

    try {
      final Map<String, dynamic> body = {
        'status': nextStatus.toApiString(),
      };
      if (estimatedMinutes != null) body['estimatedMinutes'] = estimatedMinutes;
      if (cancelReason != null) body['cancelReason'] = cancelReason;

      final res = await http.patch(
        Uri.parse('$_baseUrl/api/orders/${order.orderId}/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (res.statusCode != 200) {
        setState(() {
          order.status = prev;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Błąd zapisu statusu: ${res.statusCode}')),
          );
        }
      } else {
        _fetchOrders(silent: true);
      }
    } catch (e) {
      setState(() {
        order.status = prev;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd sieci: $e')),
        );
      }
    }
  }

  // Okienko wyboru czasu realizacji (np. 15, 20, 30, 45, 60 min)
  void _showAcceptOrderDialog(OrderModel order) {
    int selectedMinutes = 25;
    final customTimeCtrl = TextEditingController(text: '25');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E222B),
            title: Row(
              children: [
                const Icon(Icons.timer, color: Color(0xFFFB8C00)),
                const SizedBox(width: 8),
                Text('Przyjmij zamówienie #${order.orderId.split('-').last}'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Wybierz przewidywany czas przygotowania dla klienta:',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [15, 20, 25, 30, 40, 50, 60].map((mins) {
                    final isCur = selectedMinutes == mins;
                    return InkWell(
                      onTap: () {
                        setDialogState(() {
                          selectedMinutes = mins;
                          customTimeCtrl.text = mins.toString();
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isCur ? const Color(0xFFE56A18) : const Color(0xFF282D37),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isCur ? const Color(0xFFE56A18) : Colors.white24,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          '$mins min',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isCur ? Colors.white : Colors.white70,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Własny czas (min): ', style: TextStyle(color: Colors.white70)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: customTimeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) {
                          final parsed = int.tryParse(val);
                          if (parsed != null && parsed > 0) {
                            setDialogState(() {
                              selectedMinutes = parsed;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Anuluj'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFB8C00),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                icon: const Icon(Icons.check, color: Colors.white),
                label: Text(
                  'ROZPOCZNIJ ($selectedMinutes min)',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _updateOrderStatus(
                    order: order,
                    nextStatus: OrderStatus.preparing,
                    estimatedMinutes: selectedMinutes,
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // Okienko anulowania zamówienia z podaniem powodu
  void _showCancelOrderDialog(OrderModel order) {
    String selectedReason = 'Brak składników / mięsa';
    final customReasonCtrl = TextEditingController();

    final reasons = [
      'Brak składników / mięsa',
      'Zbyt duże obłożenie kuchni (czas > 90 min)',
      'Lokal wkrótce zamykany',
      'Adres dostawy poza strefą dowozu',
      'Błędne dane kontaktowe klienta',
      'Inny powód',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E222B),
            title: Row(
              children: [
                const Icon(Icons.cancel, color: Colors.redAccent),
                const SizedBox(width: 8),
                Text('Anuluj zamówienie #${order.orderId.split('-').last}'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Wybierz powód anulowania zamówienia (klient zobaczy informację na stronie):',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ...reasons.map((r) => RadioListTile<String>(
                        value: r,
                        groupValue: selectedReason,
                        dense: true,
                        activeColor: Colors.redAccent,
                        title: Text(r, style: const TextStyle(fontSize: 13)),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedReason = val);
                          }
                        },
                      )),
                  if (selectedReason == 'Inny powód')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextField(
                        controller: customReasonCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Wpisz szczegółowy powód anulowania',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Wróć'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                icon: const Icon(Icons.close, color: Colors.white),
                label: const Text(
                  'POTWIERDŹ ANULOWANIE',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  final finalReason = selectedReason == 'Inny powód' && customReasonCtrl.text.isNotEmpty
                      ? customReasonCtrl.text.trim()
                      : selectedReason;

                  Navigator.pop(ctx);
                  _updateOrderStatus(
                    order: order,
                    nextStatus: OrderStatus.cancelled,
                    cancelReason: finalReason,
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _openSettingsDialog() {
    final ipCtrl = TextEditingController(text: _serverIp);
    final portCtrl = TextEditingController(text: _serverPort);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222B),
        title: const Row(
          children: [
            Icon(Icons.settings, color: Color(0xFFE56A18)),
            SizedBox(width: 8),
            Text('Połączenie z serwerem strony'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Wpisz adres IP komputera w sieci lokalnej Wi-Fi:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ipCtrl,
              decoration: const InputDecoration(
                labelText: 'Adres IP komputera',
                hintText: 'np. 192.168.100.5',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: portCtrl,
              decoration: const InputDecoration(
                labelText: 'Port HTTP',
                hintText: '3000',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anuluj'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE56A18)),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('server_ip', ipCtrl.text.trim());
              await prefs.setString('server_port', portCtrl.text.trim());
              setState(() {
                _serverIp = ipCtrl.text.trim();
                _serverPort = portCtrl.text.trim();
              });
              if (ctx.mounted) Navigator.pop(ctx);
              _fetchOrders();
            },
            child: const Text('Zapisz i połącz', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  List<OrderModel> get _filteredOrders {
    if (_filter == 'active') {
      return _orders.where((o) =>
          o.status == OrderStatus.paid ||
          o.status == OrderStatus.preparing ||
          o.status == OrderStatus.ready).toList();
    } else if (_filter == 'paid') {
      return _orders.where((o) => o.status == OrderStatus.paid).toList();
    } else if (_filter == 'preparing') {
      return _orders.where((o) => o.status == OrderStatus.preparing).toList();
    } else if (_filter == 'ready') {
      return _orders.where((o) => o.status == OrderStatus.ready).toList();
    } else if (_filter == 'completed') {
      return _orders.where((o) => o.status == OrderStatus.completed).toList();
    } else if (_filter == 'cancelled') {
      return _orders.where((o) => o.status == OrderStatus.cancelled).toList();
    }
    return _orders;
  }

  @override
  Widget build(BuildContext context) {
    final activeOrders = _orders.where((o) =>
        o.status == OrderStatus.paid ||
        o.status == OrderStatus.preparing ||
        o.status == OrderStatus.ready).length;

    final newOrdersCount = _orders.where((o) => o.status == OrderStatus.paid).length;
    final preparingCount = _orders.where((o) => o.status == OrderStatus.preparing).length;
    final readyCount = _orders.where((o) => o.status == OrderStatus.ready).length;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFE56A18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lunch_dining, color: Colors.white, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'BUŁKA & SPÓŁKA',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.1),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF282D37),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white24),
              ),
              child: const Text(
                'KDS TABLET KUCHENNY',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _isConnected ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _isConnected ? Colors.green : Colors.red, width: 1.2),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 4,
                    backgroundColor: _isConnected ? Colors.greenAccent : Colors.redAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isConnected ? 'ONLINE: $_serverIp:$_serverPort' : 'ROZŁĄCZONO',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _isConnected ? Colors.greenAccent : Colors.redAccent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF282D37),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _buildStatBadge('NOWE', newOrdersCount, const Color(0xFFE53935)),
                  const SizedBox(width: 12),
                  _buildStatBadge('W KUCHNI', preparingCount, const Color(0xFFFB8C00)),
                  const SizedBox(width: 12),
                  _buildStatBadge('GOTOWE', readyCount, const Color(0xFF43A047)),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Odśwież listę',
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh),
            onPressed: () => _fetchOrders(),
          ),
          IconButton(
            tooltip: 'Ustawienia połączenia',
            icon: const Icon(Icons.settings),
            onPressed: _openSettingsDialog,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Pasek filtrów na tablecie
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF151820),
            child: Row(
              children: [
                _buildFilterButton('active', 'Aktywne ($activeOrders)'),
                const SizedBox(width: 8),
                _buildFilterButton('paid', 'Nowe ($newOrdersCount)'),
                const SizedBox(width: 8),
                _buildFilterButton('preparing', 'W kuchni ($preparingCount)'),
                const SizedBox(width: 8),
                _buildFilterButton('ready', 'Gotowe ($readyCount)'),
                const SizedBox(width: 8),
                _buildFilterButton('completed', 'Wydane'),
                const SizedBox(width: 8),
                _buildFilterButton('cancelled', 'Anulowane'),
                const Spacer(),
                Text(
                  DateFormat('HH:mm:ss').format(DateTime.now()),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),

          if (!_isConnected && _errorMessage.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.red.shade900,
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Brak połączenia ze stroną ($_errorMessage). Upewnij się, że tablet i komputer są w tym samym Wi-Fi.',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: _openSettingsDialog,
                    style: TextButton.styleFrom(backgroundColor: Colors.white24),
                    child: const Text('Zmień IP', style: TextStyle(color: Colors.white)),
                  )
                ],
              ),
            ),

          Expanded(
            child: _filteredOrders.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.soup_kitchen, size: 70, color: Colors.white.withOpacity(0.2)),
                        const SizedBox(height: 16),
                        Text(
                          _filter == 'active'
                              ? 'Brak aktywnych zamówień na kuchni'
                              : 'Brak zamówień w tej kategorii',
                          style: TextStyle(fontSize: 20, color: Colors.white.withOpacity(0.5)),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Zamówienia ze strony internetowej pojawią się tu w czasie rzeczywistym.',
                          style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.3)),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      int crossAxisCount = 3;
                      if (constraints.maxWidth > 1250) {
                        crossAxisCount = 4;
                      } else if (constraints.maxWidth < 850) {
                        crossAxisCount = 2;
                      }

                      return GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.72,
                        ),
                        itemCount: _filteredOrders.length,
                        itemBuilder: (context, index) {
                          final order = _filteredOrders[index];
                          return _buildOrderCard(order);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBadge(String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500),
        ),
        Text(
          '$count',
          style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildFilterButton(String key, String text) {
    final isSelected = _filter == key;
    return InkWell(
      onTap: () => setState(() => _filter = key),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE56A18) : const Color(0xFF242832),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? const Color(0xFFE56A18) : Colors.white12,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildOrderCard(OrderModel order) {
    final elapsed = order.elapsedMinutes;
    Color timerColor = Colors.white70;
    if (elapsed > 20 && order.status != OrderStatus.completed && order.status != OrderStatus.cancelled) {
      timerColor = Colors.redAccent;
    } else if (elapsed > 10 && order.status != OrderStatus.completed && order.status != OrderStatus.cancelled) {
      timerColor = Colors.orangeAccent;
    }

    final isDelivery = order.deliveryType == 'delivery';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: order.status == OrderStatus.paid
              ? const Color(0xFFE53935)
              : order.status == OrderStatus.preparing
                  ? const Color(0xFFFB8C00)
                  : Colors.white12,
          width: order.status == OrderStatus.paid ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // NAGŁÓWEK KARTY
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: const BoxDecoration(
              color: Color(0xFF242832),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '#${order.orderId.split('-').last}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDelivery ? const Color(0xFF1E88E5) : const Color(0xFF00897B),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isDelivery ? Icons.delivery_dining : Icons.storefront,
                                  size: 13,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isDelivery ? 'DOWÓZ' : 'ODBIÓR',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Złożono: ${DateFormat('HH:mm').format(order.createdAt)}',
                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: timerColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: timerColor.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer_outlined, size: 14, color: timerColor),
                      const SizedBox(width: 4),
                      Text(
                        '$elapsed min',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: timerColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // STATUS + CZAS REALIZACJI
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: order.status.color.withOpacity(0.2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.status.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: order.status.color,
                        ),
                      ),
                      if (order.estimatedMinutes != null && order.status != OrderStatus.cancelled)
                        Text(
                          'Czas dla klienta: ~${order.estimatedMinutes} min',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFFFB300),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (order.status == OrderStatus.cancelled && order.cancelReason != null)
                        Text(
                          'Powód: ${order.cancelReason}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: Colors.redAccent),
                        ),
                    ],
                  ),
                ),
                Text(
                  '${order.totalAmount.toStringAsFixed(2)} zł',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // DANE KLIENTA
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            color: const Color(0xFF161920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, size: 13, color: Colors.white60),
                    const SizedBox(width: 4),
                    Text(
                      order.customer.name,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      order.customer.phone,
                      style: const TextStyle(fontSize: 11, color: Colors.white60),
                    ),
                  ],
                ),
                if (isDelivery && order.customer.address != null && order.customer.address!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Adres: ${order.customer.address}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.amberAccent),
                    ),
                  ),
                if (order.customer.notes != null && order.customer.notes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Uwagi: ${order.customer.notes}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.orangeAccent),
                    ),
                  ),
              ],
            ),
          ),

          // POZYCJE ZAMÓWIENIA
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: order.items.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 8),
              itemBuilder: (context, idx) {
                final item = order.items[idx];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE56A18),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${item.quantity}x',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (item.meat != null || item.sauce != null || item.extras.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 28, top: 2),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: [
                            if (item.meat != null && item.meat!.isNotEmpty)
                              _buildOptionBadge('Mięso: ${item.meat}', Colors.amber),
                            if (item.sauce != null && item.sauce!.isNotEmpty)
                              _buildOptionBadge('Sos: ${item.sauce}', Colors.lightBlueAccent),
                            ...item.extras.map((e) => _buildOptionBadge('+$e', Colors.greenAccent)),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),

          // PRZYCISKI AKCJI (CZAS REALIZACJI / ANULUJ / GOTOWE / WYDANE)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFF151820),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(10),
                bottomRight: Radius.circular(10),
              ),
            ),
            child: _buildActionButtons(order),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _buildActionButtons(OrderModel order) {
    switch (order.status) {
      case OrderStatus.paid:
        // Nowe zamówienie: PRZYJMIJ (WYBIERZ CZAS) lub ANULUJ
        return Row(
          children: [
            Expanded(
              flex: 5,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFB8C00),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.timer, color: Colors.white, size: 18),
                label: const Text(
                  'PRZYJMIJ (CZAS)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                onPressed: () => _showAcceptOrderDialog(order),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('ANULUJ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: () => _showCancelOrderDialog(order),
              ),
            ),
          ],
        );

      case OrderStatus.preparing:
        return Row(
          children: [
            Expanded(
              flex: 5,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF43A047),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.check_circle, color: Colors.white, size: 18),
                label: const Text(
                  'GOTOWE DO ODBIORU',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                onPressed: () => _updateOrderStatus(
                  order: order,
                  nextStatus: OrderStatus.ready,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Zmień czas lub anuluj',
              icon: const Icon(Icons.more_vert, color: Colors.white60),
              onPressed: () => _showCancelOrderDialog(order),
            ),
          ],
        );

      case OrderStatus.ready:
        return Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E88E5),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.done_all, color: Colors.white, size: 18),
                label: const Text(
                  'WYDANO KLIENTOWI / KURIEROWI',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                onPressed: () => _updateOrderStatus(
                  order: order,
                  nextStatus: OrderStatus.completed,
                ),
              ),
            ),
          ],
        );

      case OrderStatus.completed:
        return const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                SizedBox(width: 6),
                Text('Zamówienie wydane', style: TextStyle(fontSize: 12, color: Colors.white54)),
              ],
            ),
          ),
        );

      case OrderStatus.cancelled:
        return const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cancel_outlined, size: 16, color: Colors.redAccent),
                SizedBox(width: 6),
                Text('Zamówienie anulowane', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
              ],
            ),
          ),
        );

      default:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _updateOrderStatus(
                  order: order,
                  nextStatus: OrderStatus.paid,
                ),
                child: const Text('Oznacz jako opłacone', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        );
    }
  }
}
