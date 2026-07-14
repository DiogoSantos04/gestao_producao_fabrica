import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart'; // 1. Import do ecrã de login

Future<void> main() async {
  // Garante que o motor do Flutter está pronto antes de inicializar o Supabase
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa o Supabase com as vossas credenciais do projeto
  await Supabase.initialize(
    url: 'https://hnilivakkwvnvgyblmss.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhuaWxpdmFra3d2bnZneWJsbXNzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMwOTMwNjMsImV4cCI6MjA5ODY2OTA2M30.O9MyaphRWKH1WE94giJdbmCSYA-NQIbZJFPy3Ldm04Y',
  );

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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), // Sintaxe corrigida aqui
        useMaterial3: true,
      ),
      home: const LoginScreen(), // 2. A app agora arranca na página de Login
    );
  }
}

// Mantemos o teu ecrã de listagem no main.dart para testar a transição pós-login
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
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              // Função para fazer logout e voltar ao login
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
    );
  }
}
