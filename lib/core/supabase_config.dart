import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  // URL base do vosso projeto no Supabase
  static const String url = 'https://hnilivakkwvnvgyblmss.supabase.co';
  
  // Chave pública do projeto. Continua a ser a "anon key" do dashboard; o SDK
  // é que passou a chamar-lhe publishableKey.
  static const String publishableKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhuaWxpdmFra3d2bnZneWJsbXNzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMwOTMwNjMsImV4cCI6MjA5ODY2OTA2M30.O9MyaphRWKH1WE94giJdbmCSYA-NQIbZJFPy3Ldm04Y'; // Coloquem aqui a vossa chave completa que estava no main.dart

  // Método centralizado para inicializar o Supabase no arranque da app
  static Future<void> init() async {
    await Supabase.initialize(
      url: url,
      publishableKey: publishableKey,
    );
  }

  // Atalho estático para aceder ao cliente do Supabase em qualquer ecrã
  // Em vez de: Supabase.instance.client.from(...)
  // Usam apenas: SupabaseConfig.client.from(...)
  static SupabaseClient get client => Supabase.instance.client;
}