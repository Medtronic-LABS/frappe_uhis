import frappe
from frappe.custom.doctype.property_setter.property_setter import make_property_setter

DEFAULT_WORKSPACE = "UHIS Clinical"


def execute():
	"""Make "UHIS Clinical" (the Spice dock's landing workspace, /desk/spice-next-core/uhis-clinical)
	the site's default desk landing page.

	There's no System Settings-level "default workspace" -- this is purely a per-user
	field (User.default_workspace), read into bootinfo.user.default_workspace and
	consumed by home_shell() (frappe/desk/doctype/sidebar/sidebar.py) as the
	first-priority landing target for a route that names nothing (a bare /desk visit).
	Without it, home_shell() falls back to "whichever shell this user can see the most
	entities in" -- a heuristic, not a deterministic site policy.

	Two parts, both idempotent:
	  1. A Property Setter defaulting User.default_workspace to this workspace, so a
	     newly created user gets it automatically (the same way any other DocField
	     default applies to a new document).
	  2. A one-time bulk fill for already-existing enabled System Users who haven't
	     set their own preference -- never overwrites a user who already has one.
	"""
	if not frappe.db.exists("Workspace", DEFAULT_WORKSPACE):
		return

	if not frappe.db.exists(
		"Property Setter", {"doc_type": "User", "field_name": "default_workspace", "property": "default"}
	):
		make_property_setter("User", "default_workspace", "default", DEFAULT_WORKSPACE, "Data")

	users = frappe.get_all(
		"User",
		filters={"enabled": 1, "user_type": "System User", "default_workspace": ("in", ["", None])},
		pluck="name",
	)
	for user in users:
		frappe.db.set_value("User", user, "default_workspace", DEFAULT_WORKSPACE)
