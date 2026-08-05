import 'package:flutter/material.dart';

import '../../../core/temas_cores.dart';
import '../../../models/cliente_model.dart';

/// Campo de pesquisa e filtro de estado da carteira.
///
/// O controlador é do ecrã: é ele que tem o debounce e quem decide quando ir ao
/// servidor. Aqui só se desenha, e observa-se o controlador para o botão de
/// limpar aparecer e desaparecer.
class BarraFiltrosClientes extends StatelessWidget {
  const BarraFiltrosClientes({
    super.key,
    required this.controladorPesquisa,
    required this.filtro,
    required this.aoMudarFiltro,
  });

  final TextEditingController controladorPesquisa;
  final FiltroCliente filtro;
  final ValueChanged<FiltroCliente> aoMudarFiltro;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool eMobile = constraints.maxWidth < 650;

        return eMobile
            ? Column(
                children: [
                  _campoPesquisa(),
                  const SizedBox(height: 12),
                  _dropdownFiltro(),
                ],
              )
            : Row(
                children: [
                  Expanded(flex: 3, child: _campoPesquisa()),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: _dropdownFiltro()),
                ],
              );
      },
    );
  }

  Widget _campoPesquisa() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controladorPesquisa,
      builder: (context, valor, _) {
        return TextField(
          controller: controladorPesquisa,
          decoration: InputDecoration(
            hintText: 'Pesquisar por nome, email, NIF, contacto ou morada...',
            hintStyle: const TextStyle(fontSize: 13, color: TemasCores.textoDesativado),
            prefixIcon:
                const Icon(Icons.search_rounded, size: 20, color: TemasCores.textoSecundario),
            suffixIcon: valor.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: controladorPesquisa.clear,
                  )
                : null,
            fillColor: TemasCores.superficieSuave,
            filled: true,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        );
      },
    );
  }

  Widget _dropdownFiltro() {
    return DropdownButtonFormField<FiltroCliente>(
      value: filtro,
      decoration: InputDecoration(
        fillColor: TemasCores.superficieSuave,
        filled: true,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      items: [
        for (final f in FiltroCliente.values)
          DropdownMenuItem(
            value: f,
            child: Text(f.etiqueta, style: const TextStyle(fontSize: 13)),
          ),
      ],
      onChanged: (val) {
        if (val != null) aoMudarFiltro(val);
      },
    );
  }
}
