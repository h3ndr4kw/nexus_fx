import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/widgets/file_explorer_view.dart';

void main() {
  group('splitPathCrumbs', () {
    test('POSIX path yields root plus cumulative segments', () {
      expect(splitPathCrumbs('/home/hendra/projects', windowsStyle: false), const [
        PathCrumb('/', '/'),
        PathCrumb('home', '/home'),
        PathCrumb('hendra', '/home/hendra'),
        PathCrumb('projects', '/home/hendra/projects'),
      ]);
    });

    test('POSIX root yields only the root crumb', () {
      expect(splitPathCrumbs('/', windowsStyle: false), const [PathCrumb('/', '/')]);
    });

    test('Windows drive path keeps the drive root with a backslash', () {
      expect(splitPathCrumbs(r'C:\Dev\projects', windowsStyle: true), const [
        PathCrumb('C:', r'C:\'),
        PathCrumb('Dev', r'C:\Dev'),
        PathCrumb('projects', r'C:\Dev\projects'),
      ]);
    });

    test('Windows drive root alone and forward slashes both work', () {
      expect(splitPathCrumbs(r'C:\', windowsStyle: true), const [PathCrumb('C:', r'C:\')]);
      expect(splitPathCrumbs('D:/a/b', windowsStyle: true).last, const PathCrumb('b', r'D:\a\b'));
    });
  });
}
