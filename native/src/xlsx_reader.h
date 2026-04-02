#ifndef XLSX_READER_H
#define XLSX_READER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/zip_reader.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <vector>

using namespace godot;

class XlsxReader : public RefCounted {
	GDCLASS(XlsxReader, RefCounted);

public:
	XlsxReader();
	~XlsxReader();

	Error open(const String &p_path);
	PackedStringArray get_sheet_names() const;
	Array get_sheet_data(const String &p_sheet_name);
	void close();

protected:
	static void _bind_methods();

private:
	Ref<ZIPReader> _zip;
	bool _is_open;

	// Sheet name → file path inside the zip (e.g. "xl/worksheets/sheet1.xml")
	Dictionary _sheet_name_to_path;
	// Ordered sheet names
	PackedStringArray _sheet_names;
	// Shared strings table
	std::vector<String> _shared_strings;

	// Internal parsing
	void _parse_workbook_rels();
	void _parse_workbook();
	void _parse_shared_strings();
	Array _parse_sheet(const String &p_zip_path);

	// Utility: column letter(s) → 0-based index (A=0, B=1, ..., Z=25, AA=26)
	static int _col_letter_to_index(const String &p_col);
	// Utility: extract column letters from cell reference like "C5" → "C"
	static String _extract_col_letters(const String &p_cell_ref);
};

#endif // XLSX_READER_H
