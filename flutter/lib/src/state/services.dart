import 'package:http/http.dart' as http;

import '../chains/counter_reader.dart';
import '../chains/networks.dart';
import '../rpc/rpc_pool.dart';

/// One RPC pool and one counter reader per network, created once and shared.
///
/// Keeping the pools alive means each one remembers which endpoints failed
/// recently, across screens and network switches.
class ChainServices {
  /// Pass a [client] to fake the network in tests.
  ChainServices({http.Client? client}) {
    for (final network in Networks.all) {
      final pool = RpcPool(urls: network.rpcUrls, client: client);
      _pools[network.id] = pool;
      _readers[network.id] = CounterReader.forNetwork(network, pool);
    }
  }

  final _pools = <String, RpcPool>{};
  final _readers = <String, CounterReader>{};

  RpcPool pool(Network network) => _pools[network.id]!;
  CounterReader reader(Network network) => _readers[network.id]!;
}
