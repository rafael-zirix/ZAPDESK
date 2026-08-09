// Modelos do CRM (funil de vendas). Espelham os JSONs de /crm/*.

/// Etapa (coluna) do Kanban — editável por conta.
class CrmStage {
  CrmStage({
    required this.id,
    required this.name,
    required this.color,
    required this.ordinal,
    required this.isWon,
    required this.isSystem,
  });

  final String id;
  final String name;
  final String color; // hex "#RRGGBB"
  final int ordinal;
  final bool isWon;
  final bool isSystem;

  factory CrmStage.fromJson(Map<String, dynamic> j) => CrmStage(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        color: (j['color'] ?? '#0E9384') as String,
        ordinal: (j['ordinal'] ?? 0) as int,
        isWon: (j['is_won'] ?? false) as bool,
        isSystem: (j['is_system'] ?? false) as bool,
      );
}

/// Negócio (card). Os campos contact*/owner* vêm por join, só para exibição.
class CrmDeal {
  CrmDeal({
    required this.id,
    required this.contactId,
    required this.stageId,
    required this.valueCents,
    required this.status,
    required this.sortOrder,
    this.ownerUserId,
    this.ticketId,
    this.title,
    this.source,
    this.sourceDetail,
    this.notes,
    this.nextFollowUpAt,
    this.wonAt,
    this.lostAt,
    this.lostReasonId,
    this.lostReasonName,
    this.lostNotes,
    this.contactName,
    this.contactPhone,
    this.contactCompany,
    this.ownerName,
  });

  final String id;
  final String contactId;
  String stageId; // mutável: o drag move localmente antes do servidor responder
  final String? ownerUserId;
  final String? ticketId;
  final String? title;
  final int valueCents;
  String status;
  final String? source;
  final String? sourceDetail;
  final String? notes;
  final DateTime? nextFollowUpAt;
  final DateTime? wonAt;
  final DateTime? lostAt;
  final String? lostReasonId;
  final String? lostReasonName;
  final String? lostNotes;
  int sortOrder;
  final String? contactName;
  final String? contactPhone;
  final String? contactCompany;
  final String? ownerName;

  /// Nome que o card exibe: título > empresa > nome do contato > telefone.
  String get displayName {
    for (final v in [title, contactCompany, contactName, contactPhone]) {
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return 'Sem nome';
  }

  factory CrmDeal.fromJson(Map<String, dynamic> j) => CrmDeal(
        id: j['id'] as String,
        contactId: (j['contact_id'] ?? '') as String,
        stageId: (j['stage_id'] ?? '') as String,
        ownerUserId: j['owner_user_id'] as String?,
        ticketId: j['ticket_id'] as String?,
        title: j['title'] as String?,
        valueCents: ((j['value_cents'] ?? 0) as num).toInt(),
        status: (j['status'] ?? 'open') as String,
        source: j['source'] as String?,
        sourceDetail: j['source_detail'] as String?,
        notes: j['notes'] as String?,
        nextFollowUpAt: _date(j['next_follow_up_at']),
        wonAt: _date(j['won_at']),
        lostAt: _date(j['lost_at']),
        lostReasonId: j['lost_reason_id'] as String?,
        lostReasonName: j['lost_reason_name'] as String?,
        lostNotes: j['lost_notes'] as String?,
        sortOrder: (j['sort_order'] ?? 0) as int,
        contactName: j['contact_name'] as String?,
        contactPhone: j['contact_phone'] as String?,
        contactCompany: j['contact_company'] as String?,
        ownerName: j['owner_name'] as String?,
      );

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v as String);
}

/// Etapa no funil de conversão (contagem + valor, sem perdidos).
class CrmFunnelRow {
  CrmFunnelRow({
    required this.stageId,
    required this.name,
    required this.color,
    required this.ordinal,
    required this.isWon,
    required this.dealCount,
    required this.valueCents,
  });

  final String stageId;
  final String name;
  final String color;
  final int ordinal;
  final bool isWon;
  final int dealCount;
  final int valueCents;

  factory CrmFunnelRow.fromJson(Map<String, dynamic> j) => CrmFunnelRow(
        stageId: j['stage_id'] as String,
        name: (j['name'] ?? '') as String,
        color: (j['color'] ?? '#0E9384') as String,
        ordinal: (j['ordinal'] ?? 0) as int,
        isWon: (j['is_won'] ?? false) as bool,
        dealCount: (j['deal_count'] ?? 0) as int,
        valueCents: ((j['total_value_cents'] ?? 0) as num).toInt(),
      );
}

/// Números de cima do relatório.
class CrmReportSummary {
  CrmReportSummary({
    required this.openCount,
    required this.openValue,
    required this.wonCount,
    required this.wonValue,
    required this.lostCount,
    required this.lostValue,
    required this.avgDaysToWin,
  });

  final int openCount;
  final int openValue;
  final int wonCount;
  final int wonValue;
  final int lostCount;
  final int lostValue;
  final double avgDaysToWin;

  int get total => openCount + wonCount + lostCount;
  double get conversionPct => total == 0 ? 0 : wonCount * 100 / total;

  factory CrmReportSummary.fromJson(Map<String, dynamic> j) => CrmReportSummary(
        openCount: (j['open_count'] ?? 0) as int,
        openValue: ((j['open_value_cents'] ?? 0) as num).toInt(),
        wonCount: (j['won_count'] ?? 0) as int,
        wonValue: ((j['won_value_cents'] ?? 0) as num).toInt(),
        lostCount: (j['lost_count'] ?? 0) as int,
        lostValue: ((j['lost_value_cents'] ?? 0) as num).toInt(),
        avgDaysToWin: ((j['avg_days_to_win'] ?? 0) as num).toDouble(),
      );
}

/// Perdidos agregados por motivo.
class CrmLossRow {
  CrmLossRow({required this.reason, required this.count, required this.valueCents});
  final String reason;
  final int count;
  final int valueCents;

  factory CrmLossRow.fromJson(Map<String, dynamic> j) => CrmLossRow(
        reason: (j['reason'] ?? 'Sem motivo') as String,
        count: (j['count'] ?? 0) as int,
        valueCents: ((j['value_cents'] ?? 0) as num).toInt(),
      );
}

/// Pacote completo do relatório (Funil + Métricas + Perdidos).
class CrmReport {
  CrmReport({
    required this.summary,
    required this.funnel,
    required this.losses,
    required this.lostDeals,
  });

  final CrmReportSummary summary;
  final List<CrmFunnelRow> funnel;
  final List<CrmLossRow> losses;
  final List<CrmDeal> lostDeals;

  factory CrmReport.fromJson(Map<String, dynamic> j) => CrmReport(
        summary: CrmReportSummary.fromJson((j['summary'] ?? {}) as Map<String, dynamic>),
        funnel: [
          for (final f in (j['funnel'] as List? ?? [])) CrmFunnelRow.fromJson(f)
        ],
        losses: [
          for (final l in (j['losses'] as List? ?? [])) CrmLossRow.fromJson(l)
        ],
        lostDeals: [
          for (final d in (j['lost_deals'] as List? ?? [])) CrmDeal.fromJson(d)
        ],
      );
}

/// Usuário da conta no papel de vendedor (filtro/atribuição).
class CrmSeller {
  CrmSeller({required this.id, required this.name, required this.role});
  final String id;
  final String name;
  final String role;

  factory CrmSeller.fromJson(Map<String, dynamic> j) => CrmSeller(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        role: (j['role'] ?? '') as String,
      );
}

/// Motivo de perda (editável por conta).
class CrmLossReason {
  CrmLossReason({required this.id, required this.name});
  final String id;
  final String name;

  factory CrmLossReason.fromJson(Map<String, dynamic> j) =>
      CrmLossReason(id: j['id'] as String, name: (j['name'] ?? '') as String);
}
