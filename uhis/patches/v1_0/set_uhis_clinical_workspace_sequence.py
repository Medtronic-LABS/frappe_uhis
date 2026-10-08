import frappe

WORKSPACE = "UHIS Clinical"


def execute():
	"""Make "UHIS Clinical" the first workspace frappe.views.Workspace.get_page_to_show()
	picks for a visitor with no localStorage.current_page yet (a first visit, or a
	cleared browser).

	frappe.desk.desktop.get_workspaces() orders bootinfo.workspaces by
	"sequence_id asc", and get_page_to_show() falls back to workspaces[0] when
	nothing is remembered client-side -- so the lowest sequence_id among the
	workspaces a user can see decides the default landing page in that case.
	"""
	if not frappe.db.exists("Workspace", WORKSPACE):
		return

	lowest_other = frappe.get_all(
		"Workspace",
		filters={"name": ["!=", WORKSPACE]},
		fields=["sequence_id"],
		order_by="sequence_id asc",
		limit=1,
	)
	target_sequence_id = (lowest_other[0].sequence_id - 1) if lowest_other else 0

	if frappe.db.get_value("Workspace", WORKSPACE, "sequence_id") != target_sequence_id:
		frappe.db.set_value("Workspace", WORKSPACE, "sequence_id", target_sequence_id)
