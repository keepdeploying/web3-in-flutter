import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_counter/src/chains/evm/evm_writer.dart';
import 'package:flutter_test/flutter_test.dart';

String hex(Object item) => BytesUtils.toHexString(Rlp.encode(item));

/// Examples from the Ethereum RLP specification.
void main() {
  test('encodes strings, integers and lists like the spec', () {
    expect(hex('dog'.codeUnits), '83646f67');
    expect(hex(['cat'.codeUnits, 'dog'.codeUnits]), 'c88363617483646f67');
    expect(hex(<int>[]), '80');
    expect(hex(<Object>[]), 'c0');
    expect(hex(BigInt.zero), '80');
    expect(hex(15), '0f');
    expect(hex(1024), '820400');
    expect(
      hex([
        <Object>[],
        [<Object>[]],
        [
          <Object>[],
          [<Object>[]],
        ],
      ]),
      'c7c0c1c0c3c0c1c0',
    );
    final long = 'Lorem ipsum dolor sit amet, consectetur adipisicing elit'.codeUnits;
    expect(hex(long), 'b838${BytesUtils.toHexString(long)}');
  });
}
