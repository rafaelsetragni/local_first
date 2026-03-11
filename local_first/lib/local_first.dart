library;

import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'src/backup/backup_crypto.dart';
import 'src/backup/backup_storage_provider.dart';

export 'src/backup/backup_crypto.dart';
export 'src/backup/backup_storage_provider.dart';

part 'src/backup/backup_data.dart';
part 'src/backup/backup_service.dart';
part 'src/data_sources/local_first_storage.dart';
part 'src/data_sources/key_value_storage.dart';
part 'src/data_sources/in_memory_config_key_value_storage.dart';
part 'src/data_sources/in_memory_local_first_storage.dart';
part 'src/data_sources/local_first_query.dart';
part 'src/clients/local_first_client.dart';
part 'src/events/local_first_event.dart';
part 'src/repositories/local_first_repository.dart';
part 'src/sync_strategies/data_sync_strategy.dart';
part 'src/utils/conflict_util.dart';
part 'src/utils/id_util.dart';
part 'src/utils/local_first_logger.dart';

typedef JsonMap<T> = Map<String, T>;

/// Type alias for a list of models with sync metadata.
typedef LocalFirstEvents<T> = List<LocalFirstEvent<T>>;
