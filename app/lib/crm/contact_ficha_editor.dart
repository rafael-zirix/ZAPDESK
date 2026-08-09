import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/br_docs.dart';
import '../core/phone.dart';
import '../core/theme.dart';

/// Ficha completa do CADASTRO ÚNICO (support_contacts): empresa, CPF/CNPJ com
/// validação de dígito, endereço. A mesma ficha vale para a conversa e para o
/// card do CRM — editar aqui reflete em tudo.
Future<void> showContactFicha(BuildContext context, String contactId) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _ContactFichaDialog(contactId: contactId),
  );
}

const _ufs = [
  'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS',
  'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC',
  'SP', 'SE', 'TO',
];

class _ContactFichaDialog extends StatefulWidget {
  const _ContactFichaDialog({required this.contactId});
  final String contactId;

  @override
  State<_ContactFichaDialog> createState() => _ContactFichaDialogState();
}

class _ContactFichaDialogState extends State<_ContactFichaDialog> {
  final _api = ApiClient.instance;

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String _phone = '';
  String _personType = 'pf';
  String _uf = '';

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _document = TextEditingController();
  final _company = TextEditingController();
  final _trade = TextEditingController();
  final _zip = TextEditingController();
  final _street = TextEditingController();
  final _number = TextEditingController();
  final _complement = TextEditingController();
  final _district = TextEditingController();
  final _city = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.get('/crm/contacts/${widget.contactId}/ficha');
    if (!mounted) return;
    if (!r.ok || r.data is! Map) {
      setState(() {
        _loading = false;
        _error = r.message ?? 'Erro ao carregar a ficha';
      });
      return;
    }
    final f = r.data as Map;
    String v(String k) => (f[k] ?? '') as String? ?? '';
    setState(() {
      _loading = false;
      _phone = v('phone');
      _personType = v('person_type').isEmpty ? 'pf' : v('person_type');
      _name.text = v('name');
      _email.text = v('email');
      _document.text = formatBrDoc(v('document'));
      _company.text = v('company_name');
      _trade.text = v('trade_name');
      _zip.text = v('zip_code');
      _street.text = v('street');
      _number.text = v('number');
      _complement.text = v('complement');
      _district.text = v('district');
      _city.text = v('city');
      _uf = v('state').toUpperCase();
    });
  }

  Future<void> _save() async {
    final doc = _document.text.replaceAll(RegExp(r'\D'), '');
    if (!validBrDoc(doc)) {
      setState(() => _error = doc.length <= 11
          ? 'CPF inválido — confira os dígitos.'
          : 'CNPJ inválido — confira os dígitos.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.put('/crm/contacts/${widget.contactId}/ficha', {
      'name': _name.text.trim(),
      'email': _email.text.trim(),
      'person_type': _personType,
      'document': doc,
      'company_name': _personType == 'pj' ? _company.text.trim() : '',
      'trade_name': _personType == 'pj' ? _trade.text.trim() : '',
      'zip_code': _zip.text.replaceAll(RegExp(r'\D'), ''),
      'street': _street.text.trim(),
      'number': _number.text.trim(),
      'complement': _complement.text.trim(),
      'district': _district.text.trim(),
      'city': _city.text.trim(),
      'state': _uf,
    });
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = r.message ?? 'Erro ao salvar a ficha';
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.badge_outlined, size: 20, color: AppTheme.seed),
        const SizedBox(width: 8),
        const Text('Ficha do contato'),
        const SizedBox(width: 12),
        if (_phone.isNotEmpty)
          Text(formatPhone(_phone),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
      ]),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const SizedBox(
                height: 200, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section('Identificação'),
                    Row(children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'pf', label: Text('Pessoa Física')),
                          ButtonSegment(value: 'pj', label: Text('Pessoa Jurídica')),
                        ],
                        selected: {_personType},
                        showSelectedIcon: false,
                        style: const ButtonStyle(visualDensity: VisualDensity.compact),
                        onSelectionChanged: (s) => setState(() => _personType = s.first),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    _field('Nome', _name, width: 250),
                    const SizedBox(height: 10),
                    Row(children: [
                      _field(_personType == 'pj' ? 'CNPJ' : 'CPF', _document,
                          width: 220,
                          hint: _personType == 'pj' ? '00.000.000/0000-00' : '000.000.000-00',
                          formatters: [BrDocInputFormatter()]),
                      const SizedBox(width: 12),
                      _field('E-mail', _email, width: 240),
                    ]),
                    if (_personType == 'pj') ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        _field('Razão social', _company, width: 240),
                        const SizedBox(width: 12),
                        _field('Nome fantasia', _trade, width: 220),
                      ]),
                    ],
                    const SizedBox(height: 16),
                    _section('Endereço'),
                    Row(children: [
                      _field('CEP', _zip, width: 130, hint: '00000-000', formatters: [CepInputFormatter()]),
                      const SizedBox(width: 12),
                      _field('Logradouro', _street, width: 330),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      _field('Número', _number, width: 100),
                      const SizedBox(width: 12),
                      _field('Complemento', _complement, width: 170),
                      const SizedBox(width: 12),
                      _field('Bairro', _district, width: 178),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      _field('Cidade', _city, width: 300),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 100,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _label('UF'),
                          DropdownButtonFormField<String>(
                            initialValue: _uf.isEmpty ? null : _uf,
                            items: [
                              for (final uf in _ufs)
                                DropdownMenuItem(value: uf, child: Text(uf)),
                            ],
                            onChanged: (v) => setState(() => _uf = v ?? ''),
                          ),
                        ]),
                      ),
                    ]),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy || _loading ? null : _save,
          child: Text(_busy ? 'Salvando…' : 'Salvar ficha'),
        ),
      ],
    );
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: Colors.grey.shade500)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600)),
      );

  Widget _field(String label, TextEditingController c,
      {required double width, String? hint, List<TextInputFormatter>? formatters}) {
    return SizedBox(
      width: width,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label(label),
        TextField(
          controller: c,
          inputFormatters: formatters,
          decoration: InputDecoration(hintText: hint, isDense: true),
        ),
      ]),
    );
  }
}
