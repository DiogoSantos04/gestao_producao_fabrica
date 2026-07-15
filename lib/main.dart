import 'package:flutter/material.dart';
import 'core/supabase_config.dart';
import 'core/temas_cores.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  // 1. Garante que o motor do Flutter está pronto antes do Supabase
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Inicializa o Supabase usando a vossa classe centralizada no core
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
      
      // 3. Aplica o estilo e cores globais definidos no core/temas_cores.dart
      theme: TemasCores.obterTema(),
      
      // 4. Arranca diretamente no ecrã de Login
      home: const LoginScreen(),
    );
  }
}