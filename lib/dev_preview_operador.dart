// Ficheiro temporário só para verificação visual do diálogo "Contactar
// Administrador" partilhado. Não faz parte da app — apagar depois da revisão.
import 'package:flutter/material.dart';
import 'core/supabase_config.dart';
import 'core/temas_cores.dart';
import 'screens/terminal_operador/operador_shell_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.init();
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: TemasCores.obterTema(),
    home: const OperadorShellScreen(),
  ));
}
