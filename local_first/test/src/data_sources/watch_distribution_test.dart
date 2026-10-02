import 'package:local_first/local_first.dart';

import 'watch_distribution_contract.dart';

void main() {
  watchDistributionContract(
    'InMemoryLocalFirstStorage',
    create: () async => InMemoryLocalFirstStorage(),
  );
}
