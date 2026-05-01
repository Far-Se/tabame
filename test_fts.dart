// ignore_for_file: unused_local_variable

import 'package:sqlite3/sqlite3.dart';

void main() {
  final Database db = sqlite3.openInMemory();
  db.execute(
      'CREATE TABLE nodes (id INTEGER PRIMARY KEY AUTOINCREMENT, parent_id INTEGER, name TEXT, is_directory INTEGER, times_opened INTEGER DEFAULT 0, is_searchable INTEGER DEFAULT 1);');

  db.execute('''
    CREATE VIRTUAL TABLE fts_nodes USING fts5(
      name,
      content='nodes',
      content_rowid='id',
      tokenize="trigram"
    );
  ''');

  db.execute('INSERT INTO nodes (name, is_directory) VALUES (\'hello_world.txt\', 0)');
  db.execute('INSERT INTO fts_nodes (rowid, name) VALUES (1, \'hello_world.txt\')');

  try {
    ResultSet results = db.select('SELECT * FROM fts_nodes WHERE fts_nodes MATCH \'"hello"\'');
    print('Match "hello": \${results.length}');

    // what about search like file_index_db?
    ResultSet results2 = db.select('''
        WITH RECURSIVE matched_nodes AS (
          SELECT f.rowid as id 
          FROM fts_nodes f
          JOIN nodes n ON f.rowid = n.id
          WHERE fts_nodes MATCH ? 
          ORDER BY n.times_opened DESC
          LIMIT ?
        ),
        path_cte(root_id, id, parent_id, name, is_directory, full_path) AS (
          SELECT n.id, n.id, n.parent_id, n.name, n.is_directory, n.name 
          FROM nodes n
          JOIN matched_nodes m ON n.id = m.id
          UNION ALL
          SELECT c.root_id, p.id, p.parent_id, p.name, p.is_directory, 
                 p.name || (CASE WHEN p.name LIKE '_:\\' OR p.name LIKE '\\\\%' THEN '' ELSE '\\' END) || c.full_path 
          FROM nodes p
          JOIN path_cte c ON c.parent_id = p.id
        )
        SELECT root_id, full_path, is_directory 
        FROM path_cte 
        WHERE parent_id IS NULL;
      ''', <Object?>['"hello"', 20]);

    print('matched: \${results2.length}');
  } catch (e) {
    print('Error: \$e');
  }
}
