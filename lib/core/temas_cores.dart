import 'package:flutter/material.dart';

class TemasCores {
  // Cores principais do sistema (Inspiradas no vosso relatório)
  static const Color primariaRoxa = Colors.deepPurple;
  static const Color fundoEscuroSidebar = Color(0xFF1E1E2C);
  static const Color laranjaAlerta = Colors.orange;
  static const Color verdeSucesso = Colors.green;
  static const Color vermelhoErro = Colors.red;
  
  // Tema geral da aplicação
  static ThemeData obterTema() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primariaRoxa,
        primary: primariaRoxa,
      ),
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
    );
  }
}