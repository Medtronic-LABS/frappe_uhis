import frappe


def execute():
	"""Set the site favicon to the Leapwell icon, unless someone already set one.

	Website Settings.favicon has no hooks.py-level fallback (unlike app_logo_url
	for the desk/login logo), so this has to be a DB write. Idempotent: only
	fills it in when unset, so a manually-customized favicon is never clobbered.
	"""
	if frappe.db.get_single_value("Website Settings", "favicon"):
		return

	frappe.db.set_single_value("Website Settings", "favicon", "/assets/uhis/images/leapwell-icon.svg")
