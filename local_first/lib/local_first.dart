library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

part 'src/data_sources/local_first_storage.dart';
part 'src/data_sources/local_first_query.dart';
part 'src/events/local_first_event.dart';
part 'src/clients/local_first_client.dart';
part 'src/repositories/local_first_repository.dart';
part 'src/sync_strategies/data_sync_strategy.dart';
part 'src/utils/uuid_util.dart';
part 'src/utils/value_stream.dart';
part 'src/storages/local_first_memory_storage.dart';
part 'src/storages/local_first_memory_key_value_storage.dart';
part 'src/utils/conflict_util.dart';
part 'src/data_sources/local_first_key_value_storage.dart';

typedef JsonMap<T> = Map<String, T>;
