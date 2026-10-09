import frappe
from frappe.utils import cint


def execute():
	"""Correct a stale "desktop:home_page" default left over from initial site setup.

	frappe.utils.install.setup_complete() sets this default to "setup-wizard" once,
	during bench new-site, only if no default exists yet. It is never updated again
	when setup actually completes. Before Frappe's v16.36 dock/sidebar rework this
	was harmless -- the old UI's root-route resolution didn't treat the stored value
	as a literal page name. Since that rework, frappe.public.js.frappe.views.pageview
	resolves an empty route by rendering whatever frappe.boot.home_page names
	(boot.py's add_home_page() reads this same default) -- so a site stuck on
	"setup-wizard" with setup actually complete renders the Setup Wizard page for a
	bare /desk visit. The wizard itself then sees System Settings.setup_complete and
	redirects back to /desk, which again resolves to "setup-wizard": an infinite
	client-side redirect loop.

	Mirrors the correction frappe.patches.v13_0.reset_corrupt_defaults already makes
	for this same field (gated there behind an unrelated 2FA-parent-corruption
	check, so it never ran for a site like this one that never hit that bug).
	"""
	if frappe.db.get_default("desktop:home_page") != "setup-wizard":
		return

	if not cint(frappe.db.get_single_value("System Settings", "setup_complete")):
		return

	frappe.db.set_default("desktop:home_page", "workspace")
