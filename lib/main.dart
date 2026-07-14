import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart'; 
import 'screens/criar_encomenda_screen.dart';
import 'screens/terminal_operador_screen.dart'; 
import 'screens/rastreio_cliente_screen.dart'; // Import do rastreio do cliente
import 'core/supabase_config.dart';

Future<void> main() async {
  // Garante que o motor do Flutter está pronto antes de inicializar o Supabase
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa o Supabase usando a vossa nova classe centralizada
  await SupabaseConfig.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Controlo de Produção',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const LoginScreen(), // A app arranca na página de Login
    );
  }
}

// Ecrã de listagem de encomendas (Painel de Controlo Principal)
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<dynamic> _encomendas = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _buscarEncomendas();
  }

  Future<void> _buscarEncomendas() async {
    try {
      final data = await Supabase.instance.client
          .from('encomendas')
          .select('id, codigo_rastreio, data_entrega');

      setState(() {
        _encomendas = data;
        _isLoading = false;
      });
    } catch (error) {
      print('Erro ao carregar dados do Supabase: $error');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          // Botão para abrir o Terminal do Operador
          IconButton(
            icon: const Icon(Icons.computer, color: Colors.deepPurple),
            tooltip: 'Abrir Terminal Operador',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const TerminalOperadorScreen()),
              );
            },
          ),
          // Botão de Logout
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              }
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _encomendas.isEmpty
              ? const Center(child: Text('Nenhuma encomenda encontrada.'))
              : ListView.builder(
                  itemCount: _encomendas.length,
                  itemBuilder: (context, index) {
                    final encomenda = _encomendas[index];
                    return ListTile(
                      leading: const Icon(Icons.inventory, color: Colors.blue),
                      title: Text('Código: ${encomenda['codigo_rastreio']}'),
                      subtitle: Text('Entrega prevista: ${encomenda['data_entrega']}'),
                    );
                  },
                ),
      // Botão para abrir o formulário de nova encomenda (Administrador)
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        onPressed: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const CriarEncomendaScreen()),
          );
          if (result == true) {
            setState(() {
              _isLoading = true;
            });
            _buscarEncomendas();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}