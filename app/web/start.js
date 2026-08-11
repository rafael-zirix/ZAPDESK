// Landing do HotZap — JS em arquivo separado (NÃO inline no index.html) porque a
// CSP do site é `script-src 'self'` sem 'unsafe-inline': script embutido no HTML
// (ou handler onsubmit=) seria bloqueado pelo navegador. Servido de 'self' passa.
(function () {
  var y = document.getElementById('y');
  if (y) y.textContent = new Date().getFullYear();

  // Login: leva o e-mail digitado para o painel (?email=). O código real é lá.
  function goLogin(e) {
    if (e) e.preventDefault();
    var el = document.getElementById('email');
    var email = ((el && el.value) || '').trim();
    var url = '/app/';
    if (email) url += '?email=' + encodeURIComponent(email);
    window.location.href = url;
    return false;
  }
  var form = document.getElementById('loginForm');
  if (form) form.addEventListener('submit', goLogin);

  // Planos: puxados do backend (/public/packages). É a MESMA lista que o
  // super-admin edita — publicar lá atualiza o site sozinho.
  (function loadPlanos() {
    var brl = new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    var reais = function (cents) { return brl.format((cents || 0) / 100); };
    var ck = '<svg viewBox="0 0 24 24" fill="none"><path d="M5 12l4 4L19 7" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    var li = function (txt, on) {
      return '<li class="' + (on ? '' : 'off') + '">' + ck + '<span>' + txt + '</span></li>';
    };
    fetch('/public/packages').then(function (r) { return r.json(); }).then(function (res) {
      var pks = (res && res.data) || [];
      if (!pks.length) return; // sem pacotes publicados: seção fica oculta
      var feat = pks.length >= 3 ? Math.floor(pks.length / 2) : -1;
      var html = pks.map(function (p, i) {
        var free = (p.price_month_cents || 0) === 0;
        var preco = free
          ? '<div class="pfree">Grátis</div>'
          : '<div class="pprice"><span class="rs">R$</span><span class="val">' + reais(p.price_month_cents) + '</span><span class="per">/mês</span></div>';
        var itens = '';
        itens += li('<b>' + (p.inc_lines || 1) + '</b> linha' + ((p.inc_lines || 1) > 1 ? 's' : '') + ' de WhatsApp', true);
        itens += li('<b>' + (p.inc_agents || 1) + '</b> atendentes', true);
        itens += li('Atendente de IA 24/7', p.inc_ia);
        itens += li('Instagram — Direct e Lead Ads', p.inc_instagram);
        itens += li('Campanhas em massa', p.inc_campanhas);
        itens += li('Métricas e relatórios', p.inc_metricas);
        itens += li('CRM — quadro e funil', p.inc_crm);
        itens += li('Leads & Qualificação', p.inc_leads);
        // Franquia em TOKENS (melhor caso: a IA mais barata do pacote rende mais).
        var bestTokens = 0;
        if (p.inc_ia && (p.franchise_cents || 0) > 0 && p.ai_prices) {
          for (var k in p.ai_prices) {
            var v = p.ai_prices[k];
            if (v > 0) {
              var t = Math.round((p.franchise_cents / 100) / v * 1000000);
              if (t > bestTokens) bestTokens = t;
            }
          }
        }
        var tokfmt = function (n) { return n >= 1000000 ? (n / 1000000).toFixed(1) + 'M' : n >= 1000 ? Math.round(n / 1000) + 'k' : '' + n; };
        var fran = bestTokens > 0
          ? '<div class="pfran">até ' + tokfmt(bestTokens) + ' tokens/mês de IA</div>'
          : ((p.inc_ia && (p.franchise_cents || 0) > 0)
            ? '<div class="pfran">R$ ' + reais(p.franchise_cents) + '/mês de IA inclusos</div>' : '');
        return '<div class="pcard' + (i === feat ? ' feat-plan' : '') + '">' +
          (i === feat ? '<span class="flag">Mais popular</span>' : '') +
          '<div class="pname">' + (p.name || 'Plano') + '</div>' +
          preco +
          '<ul>' + itens + '</ul>' + fran +
          '<a class="btn lg" style="width:auto" href="/app/?signup=1">' + (free ? 'Começar grátis' : 'Quero este plano') + '</a>' +
          '</div>';
      }).join('');
      var grid = document.getElementById('pgrid');
      var sec = document.getElementById('planos');
      if (grid) grid.innerHTML = html;
      if (sec) sec.hidden = false;
    }).catch(function () { /* silêncio: se a API falhar, o site segue sem a seção */ });
  })();
})();
