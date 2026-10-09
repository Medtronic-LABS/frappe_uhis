import frappe


def set_home_page_to_workspaces(bootinfo):
	"""Route the empty-route desk landing through the real Workspace view, not the legacy
	Page-based desktop icon grid.

	frappe.boot.add_home_page() resolves the "desktop:home_page" default as a `Page`
	document name. No Page named "workspace" ships with this Frappe version (only
	"desktop" and "workspace_restore" do), so that lookup always raises
	DoesNotExistError and add_home_page() falls back to its hardcoded literal
	"desktop" -- frappe.boot.home_page ends up naming the Desktop icon-grid Apps
	screen for every bare "/desk" or "/" visit, no matter what "desktop:home_page"
	is set to.

	"Workspaces" is a different, JS-registered standard page
	(frappe.standard_pages["Workspaces"] in workspace.js) that never does that Page
	lookup -- it goes straight to frappe.views.Workspace, which resolves the
	current user's actual default workspace (the last one they visited, else the
	lowest-sequence_id workspace they can see) and rewrites the URL to it via
	frappe.set_route(). Pointing bootinfo.home_page there instead is what actually
	makes a workspace the desk's landing page.
	"""
	if not bootinfo.get("user"):
		return

	bootinfo["home_page"] = "Workspaces"
