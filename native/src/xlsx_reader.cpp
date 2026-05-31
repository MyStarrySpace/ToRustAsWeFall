#include "xlsx_reader.h"

#include <godot_cpp/classes/xml_parser.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

XlsxReader::XlsxReader() :
		_is_open(false) {
}

XlsxReader::~XlsxReader() {
	close();
}

void XlsxReader::_bind_methods() {
	ClassDB::bind_method(D_METHOD("open", "path"), &XlsxReader::open);
	ClassDB::bind_method(D_METHOD("get_sheet_names"), &XlsxReader::get_sheet_names);
	ClassDB::bind_method(D_METHOD("get_sheet_data", "sheet_name"), &XlsxReader::get_sheet_data);
	ClassDB::bind_method(D_METHOD("close"), &XlsxReader::close);
}

Error XlsxReader::open(const String &p_path) {
	close();

	_zip.instantiate();
	Error err = _zip->open(p_path);
	if (err != OK) {
		UtilityFunctions::push_error("XlsxReader: Could not open zip: " + p_path);
		_zip.unref();
		return err;
	}
	_is_open = true;

	_parse_workbook_rels();
	_parse_workbook();
	_parse_shared_strings();

	return OK;
}

PackedStringArray XlsxReader::get_sheet_names() const {
	return _sheet_names;
}

Array XlsxReader::get_sheet_data(const String &p_sheet_name) {
	if (!_is_open) {
		UtilityFunctions::push_error("XlsxReader: Not open");
		return Array();
	}
	if (!_sheet_name_to_path.has(p_sheet_name)) {
		UtilityFunctions::push_error("XlsxReader: Sheet not found: " + p_sheet_name);
		return Array();
	}
	String zip_path = _sheet_name_to_path[p_sheet_name];
	return _parse_sheet(zip_path);
}

void XlsxReader::close() {
	if (_is_open && _zip.is_valid()) {
		_zip->close();
	}
	_zip.unref();
	_is_open = false;
	_sheet_name_to_path.clear();
	_sheet_names = PackedStringArray();
	_shared_strings.clear();
}

void XlsxReader::_parse_workbook_rels() {
	String rels_path = "xl/_rels/workbook.xml.rels";
	if (!_zip->file_exists(rels_path)) {
		UtilityFunctions::push_error("XlsxReader: Missing " + rels_path);
		return;
	}

	PackedByteArray data = _zip->read_file(rels_path);
	Ref<XMLParser> xml;
	xml.instantiate();
	xml->open_buffer(data);

	Dictionary rels_map;

	while (xml->read() == OK) {
		if (xml->get_node_type() == XMLParser::NODE_ELEMENT && xml->get_node_name() == "Relationship") {
			String id = xml->get_named_attribute_value_safe("Id");
			String target = xml->get_named_attribute_value_safe("Target");
			if (!id.is_empty() && !target.is_empty()) {
				// Handle both relative ("worksheets/sheet1.xml") and
				// absolute ("/xl/worksheets/sheet1.xml") Target paths
				if (target.begins_with("/")) {
					rels_map[id] = target.substr(1);
				} else {
					rels_map[id] = "xl/" + target;
				}
			}
		}
	}

	_sheet_name_to_path = rels_map;
}

void XlsxReader::_parse_workbook() {
	String wb_path = "xl/workbook.xml";
	if (!_zip->file_exists(wb_path)) {
		UtilityFunctions::push_error("XlsxReader: Missing " + wb_path);
		return;
	}

	PackedByteArray data = _zip->read_file(wb_path);
	Ref<XMLParser> xml;
	xml.instantiate();
	xml->open_buffer(data);

	Dictionary rels_map = _sheet_name_to_path.duplicate();
	_sheet_name_to_path.clear();

	while (xml->read() == OK) {
		if (xml->get_node_type() == XMLParser::NODE_ELEMENT && xml->get_node_name() == "sheet") {
			String name = xml->get_named_attribute_value_safe("name");
			String r_id = xml->get_named_attribute_value_safe("r:id");
			if (!name.is_empty() && rels_map.has(r_id)) {
				_sheet_names.push_back(name);
				_sheet_name_to_path[name] = rels_map[r_id];
			}
		}
	}
}

void XlsxReader::_parse_shared_strings() {
	String ss_path = "xl/sharedStrings.xml";
	if (!_zip->file_exists(ss_path)) {
		return;
	}

	PackedByteArray data = _zip->read_file(ss_path);
	Ref<XMLParser> xml;
	xml.instantiate();
	xml->open_buffer(data);

	bool in_si = false;
	String current_text;

	while (xml->read() == OK) {
		XMLParser::NodeType type = xml->get_node_type();

		// get_node_name() must only be called on element nodes; calling it on a
		// NODE_TEXT (the string contents themselves) raises an engine error, and
		// the shared-strings table is almost entirely text nodes.
		if (type == XMLParser::NODE_ELEMENT) {
			if (xml->get_node_name() == "si") {
				in_si = true;
				current_text = "";
			}
		} else if (type == XMLParser::NODE_ELEMENT_END) {
			if (xml->get_node_name() == "si") {
				_shared_strings.push_back(current_text);
				in_si = false;
			}
		} else if (type == XMLParser::NODE_TEXT) {
			if (in_si) {
				current_text += xml->get_node_data();
			}
		}
	}
}

Array XlsxReader::_parse_sheet(const String &p_zip_path) {
	if (!_zip->file_exists(p_zip_path)) {
		UtilityFunctions::push_error("XlsxReader: Missing sheet file " + p_zip_path);
		return Array();
	}

	PackedByteArray data = _zip->read_file(p_zip_path);
	Ref<XMLParser> xml;
	xml.instantiate();
	xml->open_buffer(data);

	Array rows;
	Array current_row;
	int current_row_max_col = -1;
	bool in_row = false;
	bool in_cell = false;
	bool in_value = false;
	String cell_type;
	String cell_ref;
	String cell_value;

	while (xml->read() == OK) {
		XMLParser::NodeType type = xml->get_node_type();

		if (type == XMLParser::NODE_ELEMENT) {
			String node_name = xml->get_node_name();
			if (node_name == "row") {
				in_row = true;
				current_row = Array();
				current_row_max_col = -1;
			} else if (node_name == "c" && in_row) {
				in_cell = true;
				cell_type = xml->get_named_attribute_value_safe("t");
				cell_ref = xml->get_named_attribute_value_safe("r");
				cell_value = "";
			} else if (node_name == "v" && in_cell) {
				in_value = true;
				cell_value = "";
			} else if (node_name == "t" && in_cell) {
				in_value = true;
				cell_value = "";
			}
		} else if (type == XMLParser::NODE_ELEMENT_END) {
			String node_name = xml->get_node_name();
			if (node_name == "row") {
				if (current_row.size() > 0 || current_row_max_col >= 0) {
					rows.push_back(current_row);
				}
				in_row = false;
			} else if (node_name == "c" && in_cell) {
				String col_letters = _extract_col_letters(cell_ref);
				int col_idx = _col_letter_to_index(col_letters);

				while (current_row.size() <= col_idx) {
					current_row.push_back(String(""));
				}

				String resolved;
				if (cell_type == "s") {
					int idx = cell_value.to_int();
					if (idx >= 0 && idx < (int)_shared_strings.size()) {
						resolved = _shared_strings[idx];
					}
				} else if (cell_type == "inlineStr") {
					resolved = cell_value;
				} else {
					resolved = cell_value;
				}

				current_row[col_idx] = resolved;
				if (col_idx > current_row_max_col) {
					current_row_max_col = col_idx;
				}

				in_cell = false;
				in_value = false;
			} else if ((node_name == "v" || node_name == "t") && in_value) {
				in_value = false;
			}
		} else if (type == XMLParser::NODE_TEXT) {
			if (in_value) {
				cell_value += xml->get_node_data();
			}
		}
	}

	return rows;
}

int XlsxReader::_col_letter_to_index(const String &p_col) {
	int result = 0;
	for (int i = 0; i < p_col.length(); i++) {
		char32_t c = p_col[i];
		result = result * 26 + (c - 'A' + 1);
	}
	return result - 1;
}

String XlsxReader::_extract_col_letters(const String &p_cell_ref) {
	String letters;
	for (int i = 0; i < p_cell_ref.length(); i++) {
		char32_t c = p_cell_ref[i];
		if (c >= 'A' && c <= 'Z') {
			letters += String::chr(c);
		} else {
			break;
		}
	}
	return letters;
}
