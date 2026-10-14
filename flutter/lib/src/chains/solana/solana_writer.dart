import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';

import '../../wallet/wallet_signer.dart';
import '../counter_reader.dart';
import '../counter_writer.dart';
import 'solana_reader.dart';

/// Calls the Anchor program's `increment`, `decrement` or `reset`
/// instruction in a Solana transaction.
class SolanaWriter extends CounterWriter {
  SolanaWriter(super.network, super.pool);

  /// The System Program, which Anchor's `init_if_needed` uses to create the
  /// user's counter account on their first call.
  static const systemProgram = '11111111111111111111111111111111';

  @override
  Future<TxResult> send(CounterAction action, WalletSigner wallet, {OnTxStep? onStep}) async {
    if (wallet is! SolanaTransactionSigner) throw unsupported(wallet);
    final signer = wallet;
    final watch = Stopwatch()..start();
    final programId = Base58Decoder.decode(network.counter);
    final user = Base58Decoder.decode(signer.address);
    final global = findProgramAddress([utf8.encode('global')], programId);
    final counter = findProgramAddress([utf8.encode('counter'), user], programId);

    // Anchor names each instruction by the first 8 bytes of
    // sha256("global:<name>"). No arguments follow.
    final data = QuickCrypto.sha256Hash(utf8.encode('global:${action.name}')).sublist(0, 8);
    onStep?.call(
      TxStep(
        'Build the instruction',
        detail:
            'Program ${network.counter}, data = the first 8 bytes of sha256("global:${action.name}"). '
            'Accounts, in the order the program declares them: the Global PDA and your Counter PDA (both '
            'writable, created on first use), you (signer, pays the fees) and the System Program.',
        code: BytesUtils.toHexString(data),
      ),
    );

    final blockhash =
        ((await pool.jsonRpc('getLatestBlockhash', [
              {'commitment': 'confirmed'},
            ]) as Map)['value']
            as Map)['blockhash'];
    onStep?.call(
      TxStep(
        'Get a recent blockhash',
        detail:
            'It dates the transaction: the network drops it if it is not processed within about a minute, '
            'so a signed transaction can never be replayed later.',
        code: blockhash as String,
      ),
    );

    // The message. Account keys are sorted by role: signers that write,
    // then accounts that are only written, then read-only ones. The header
    // says how many of each, so the keys themselves carry no flags.
    final keys = [
      user,
      Base58Decoder.decode(global),
      Base58Decoder.decode(counter),
      Base58Decoder.decode(systemProgram),
      programId,
    ];
    final message = [
      1, // signatures required: the user
      0, // read-only signers
      2, // read-only non-signers: the System Program and the program itself
      ...shortVec(keys.length),
      for (final key in keys) ...key,
      ...Base58Decoder.decode(blockhash),
      ...shortVec(1), // one instruction
      4, // its program: keys[4]
      ...shortVec(4), 1, 2, 0, 3, // its accounts: global, counter, user, system program
      ...shortVec(data.length), ...data,
    ];
    // The transaction is the signatures followed by the message. The
    // wallet fills in the one signature slot.
    askToApprove(signer, onStep);
    final transaction = await signer.signSolanaTransaction([
      ...shortVec(1),
      ...List.filled(64, 0),
      ...message,
    ], network);
    onStep?.call(
      TxStep(
        'Signed',
        detail:
            'An ed25519 signature over the message bytes, in front of the message: ${transaction.length} bytes, '
            'well under the 1232-byte limit.',
        code: base64Encode(transaction),
      ),
    );

    final txId = await pool.jsonRpc('sendTransaction', [
      base64Encode(transaction),
      {'encoding': 'base64', 'preflightCommitment': 'confirmed'},
    ]) as String;
    onStep?.call(
      TxStep(
        'Send it',
        detail:
            'sendTransaction simulated it first (the preflight) and returned the signature, which is also the '
            'transaction ID.',
        code: txId,
      ),
    );

    final status = await CounterWriter.waitFor(() async {
      final result = await pool.jsonRpc('getSignatureStatuses', [
        [txId],
      ]) as Map;
      final status = (result['value'] as List).first as Map?;
      final level = status?['confirmationStatus'];
      return level == 'confirmed' || level == 'finalized' ? status : null;
    }, every: const Duration(milliseconds: 800));
    if (status['err'] != null) throw TxException('The program returned an error: ${status['err']}');
    onStep?.call(
      TxStep(
        'Confirmed in slot ${status['slot']}',
        detail: 'A supermajority of validators voted for the block that holds it.',
      ),
    );
    return TxResult(txId: txId, elapsed: watch.elapsed);
  }

  /// Solana's compact length ("short vec"): 7 bits per byte, low bits
  /// first, high bit set while more bytes follow.
  static List<int> shortVec(int value) {
    final out = <int>[];
    do {
      var byte = value & 0x7f;
      value >>= 7;
      if (value != 0) byte |= 0x80;
      out.add(byte);
    } while (value != 0);
    return out;
  }
}
