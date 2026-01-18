import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/generator/offline_entity_generator.dart';

/// Builder for offline entity code generation
Builder offlineEntityBuilder(BuilderOptions options) {
  return SharedPartBuilder(
    [OfflineEntityGenerator()],
    'offline_entity',
  );
}
