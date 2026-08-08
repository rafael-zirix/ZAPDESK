// Integração com a Meta (Embedded Signup do WhatsApp + login do Instagram).
//
// Vive em arquivo separado, e não inline no index.html, porque a CSP do painel
// usa script-src 'self' sem 'unsafe-inline': script embutido no HTML seria
// bloqueado pelo navegador e os dois botões parariam de funcionar.

// Retorno do diálogo OAuth da Meta: esta MESMA página é o redirect_uri, e
// quando ela abre dentro do popup só precisa devolver o código a quem abriu.
// Roda antes do Flutter de propósito — não faz sentido subir o app inteiro
// numa janela que vai fechar em seguida.
(function () {
  try {
    var q = new URLSearchParams(window.location.search);
    var code = q.get('code');
    var state = q.get('state') || '';
    if (window.opener && code && state.indexOf('zapfb') === 0) {
      window.opener.postMessage({ type: 'ZAP_FB_CODE', code: code, state: state }, window.location.origin);
      window.close();
    }
  } catch (e) {}
})();

window.zapEmbeddedSignup = function (appId, configId, graphVersion) {
  return new Promise(function (resolve, reject) {
    var session = {};
    function onMessage(event) {
      try {
        if ((event.origin || '').indexOf('facebook.com') === -1) return;
        var data = typeof event.data === 'string' ? JSON.parse(event.data) : event.data;
        if (data && data.type === 'WA_EMBEDDED_SIGNUP' && data.data) session = data.data;
      } catch (e) {}
    }
    function launch() {
      window.addEventListener('message', onMessage);
      window.FB.login(function (response) {
        window.removeEventListener('message', onMessage);
        var code = response && response.authResponse && response.authResponse.code;
        if (code) {
          resolve({ code: code, waba_id: session.waba_id || '', phone_number_id: session.phone_number_id || '' });
        } else {
          resolve(null); // usuário cancelou
        }
      }, {
        config_id: configId,
        response_type: 'code',
        override_default_response_type: true,
        extras: { sessionInfoVersion: 3 }
      });
    }
    if (window.FB) { launch(); return; }
    window.fbAsyncInit = function () {
      window.FB.init({ appId: appId, autoLogAppEvents: true, xfbml: false, version: graphVersion });
      launch();
    };
    var js = document.createElement('script');
    js.async = true;
    js.src = 'https://connect.facebook.net/en_US/sdk.js';
    js.onerror = function () { reject('sdk_load_failed'); };
    document.body.appendChild(js);
  });
};

// Login da Meta para o Instagram, por diálogo OAuth explícito.
//
// Por que não o FB.login do SDK: o popup dele devolve um código atrelado a um
// redirect_uri interno do Facebook, e a troca no servidor é recusada com
// subcode 36008 — com ou sem redirect_uri. Abrindo o diálogo nós mesmos, o
// redirect_uri é a nossa própria página (que já está na lista de URIs válidos
// do app), e o mesmo valor vai no diálogo e na troca. Sem adivinhação.
window.zapFacebookLogin = function (appId, configId, graphVersion) {
  return new Promise(function (resolve) {
    var redirect = window.location.origin + window.location.pathname;
    var state = 'zapfb' + String(Date.now());
    var url = 'https://www.facebook.com/' + graphVersion + '/dialog/oauth' +
      '?client_id=' + encodeURIComponent(appId) +
      '&config_id=' + encodeURIComponent(configId) +
      '&response_type=code' +
      '&override_default_response_type=true' +
      '&state=' + encodeURIComponent(state) +
      '&redirect_uri=' + encodeURIComponent(redirect);
    var win = window.open(url, 'zap_fb_login', 'width=700,height=760');
    if (!win) { resolve(null); return; } // popup bloqueado
    var pronto = false;
    function onMessage(ev) {
      if (ev.origin !== window.location.origin) return;
      var d = ev.data || {};
      if (d.type !== 'ZAP_FB_CODE' || d.state !== state) return;
      pronto = true;
      cleanup();
      resolve({ code: d.code, redirect_uri: redirect });
    }
    function cleanup() {
      window.removeEventListener('message', onMessage);
      clearInterval(vigia);
    }
    window.addEventListener('message', onMessage);
    // Se a pessoa fechar o popup no braço, ninguém avisa: o vigia desiste.
    var vigia = setInterval(function () {
      if (win.closed && !pronto) { cleanup(); resolve(null); }
    }, 500);
  });
};
