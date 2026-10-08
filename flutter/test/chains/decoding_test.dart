import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_counter/src/chains/counter_reader.dart';
import 'package:flutter_counter/src/chains/evm/evm_reader.dart';
import 'package:flutter_counter/src/chains/solana/solana_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EVM selectors and event topic match the deployed contract', () {
    // Checked against `cast sig` and `cast keccak`.
    expect(EvmReader.selector('increment()'), '0xd09de08a');
    expect(EvmReader.selector('totalUsers()'), '0xbff1f9e1');
    expect(EvmReader.counterChangedTopic.length, 66);
  });

  test('Solana PDAs match the ones the Anchor program uses', () {
    final program = Base58Decoder.decode('B5FWXqM3hrna9SCPp2r2APzEmaMzash3N6t9kkwpD5qH');
    // Derived independently with solders (Python) for the dev wallet.
    expect(findProgramAddress(['global'.codeUnits], program), '33XWrF5f4zPQMRTqqLhEw3pwpLa34XvsYknvtewdNDpC');
    final user = Base58Decoder.decode('DfmTeaToGmhvmzxFA4fCVZJZhdj4HJm2RAvnHSXdkGqX');
    expect(findProgramAddress(['counter'.codeUnits, user], program), 'BSExN6yuoJt5TfvgfMwpms2RKuJXERmgKZ8zkxip2GXL');
  });

  test('formats amounts in the smallest unit', () {
    expect(formatUnits(BigInt.parse('1234500000000000000'), 18), '1.2345');
    expect(formatUnits(BigInt.from(5000000000), 9), '5');
    expect(formatUnits(BigInt.zero, 24), '0');
    expect(formatUnits(BigInt.from(49440000), 6), '49.44');
  });

  test('EVM addresses get their EIP-55 checksum casing', () {
    expect(
      EvmReader.checksumAddress('0xfffaa29e82d5455985a908235536d2cd01acce47'),
      '0xfFFAa29e82d5455985a908235536d2cD01aCce47',
    );
  });

  test('reads 64-bit Borsh integers without 64-bit ByteData (web-safe)', () {
    List<int> le(int v) => [for (var i = 0; i < 8; i++) (BigInt.from(v) >> (8 * i)).toUnsigned(8).toInt()];
    expect(readU64(le(5), 0), 5);
    expect(readU64(le(0x123456789), 0), 0x123456789);
    expect(readI64(le(-1), 0), -1);
    expect(readI64(le(-0x123456789), 0), -0x123456789);
    expect(readI64([0, 0, ...le(42)], 2), 42);
  });
}
