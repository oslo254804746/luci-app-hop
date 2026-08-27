'use strict';
'require view';
'require form';
'require fs';
'require ui';

return view.extend({
	load: function() {
		return L.resolveDefault(fs.exec('/usr/share/hop/hop-core', [ 'status' ]), {
			stdout: _('Hop core status is unavailable.')
		});
	},

	render: function(data) {
		var m, o, s;
		var coreStatus = (data.stdout || data.stderr || '').trim();
		var officialReleaseBase = 'https://github.com/oslo254804746/hop-rs/releases';
		var ghProxyReleaseBase = 'https://gh-proxy.net/' + officialReleaseBase;

		m = new form.Map('hop', _('Hop'),
			_('This page controls the service and verified core download. Use the Management Panel tab for assets, credentials, Access Keys and sessions.'));

		s = m.section(form.TypedSection, 'hop', _('Service'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.rmempty = false;

		o = s.option(form.Value, 'config_path', _('Startup configuration'));
		o.default = '/etc/hop/config.toml';
		o.rmempty = false;

		o = s.option(form.Flag, 'auto_download', _('Download missing core on start'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'core_version', _('Core release'));
		o.default = 'v0.2.8';
		o.rmempty = false;
		o.description = _('Use latest, a tag such as v0.2.8, or a version such as 0.2.8. Keeping the bundled version avoids frontend/API mismatches.');

		o = s.option(form.Value, 'release_base', _('Core download source'));
		o.default = officialReleaseBase;
		o.rmempty = false;
		o.value(officialReleaseBase, _('Official GitHub Releases'));
		o.value(ghProxyReleaseBase, _('gh-proxy.net mirror (third party)'));
		o.description = _('Choose a preset or enter a custom GitHub-compatible Releases base URL. Third-party mirrors can replace both the archive and its checksum; use only a provider you trust.');
		o.validate = function(sectionId, value) {
			if (!/^https:\/\/[^\s?#]+$/.test(value))
				return _('Use an HTTPS URL without a query string or fragment.');
			return true;
		};

		o = s.option(form.Flag, 'log_stdout', _('Log standard output'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Flag, 'log_stderr', _('Log standard error'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.DummyValue, '_core_status', _('Core status'));
		o.default = coreStatus || _('Not installed');
		o.cfgvalue = function() {
			return coreStatus || _('Not installed');
		};

		o = s.option(form.Button, '_update_core', _('Core download'));
		o.inputtitle = _('Download / update core');
		o.inputstyle = 'apply';
		o.onclick = function() {
			ui.showModal(_('Downloading Hop core'), [
				E('p', { 'class': 'spinning' }, _('Downloading and verifying the architecture-specific release asset…'))
			]);
			return fs.exec('/usr/share/hop/hop-core', [ 'update' ]).then(function(result) {
				coreStatus = (result.stdout || result.stderr || '').trim();
				ui.addNotification(null, E('p', _('Hop core was installed successfully.')), 'info');
				window.location.reload();
			}).catch(function(error) {
				ui.addNotification(null, E('p', error.message), 'error');
			}).finally(function() {
				ui.hideModal();
			});
		};

		o = s.option(form.Button, '_restart', _('Service action'));
		o.inputtitle = _('Restart Hop');
		o.inputstyle = 'action';
		o.onclick = function() {
			return fs.exec('/etc/init.d/hop', [ 'restart' ]).then(function() {
				ui.addNotification(null, E('p', _('Hop restart was requested.')), 'info');
			}).catch(function(error) {
				ui.addNotification(null, E('p', error.message), 'error');
			});
		};

		return m.render();
	}
});
