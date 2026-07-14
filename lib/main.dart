import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: .fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

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

  // Função para testar a ligação e ler dados do Supabase
  Future<void> _buscarEncomendas() async {
    try {
      final data = await Supabase.instance.client
          .from('encomendas')
          .select('id, codigo_rastreio, data_entrega'); // Lê os dados de teste da tabela encomendas

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
