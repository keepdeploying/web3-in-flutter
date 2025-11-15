import 'package:solana/dto.dart';
import 'package:solana/solana.dart';

Future<String?> getSolanaBalance(String rpcUrl, String walletAddress) async {
  final rpcClient = RpcClient(rpcUrl);
  final publicKey = Ed25519HDPublicKey.fromBase58(walletAddress);
  final balanceResult = await rpcClient.getBalance(publicKey.toBase58());
  final solBalance = balanceResult.value / lamportsPerSol;
  return '${solBalance.toStringAsFixed(9)} SOL';
}

Future<String?> getSplTokenBalance(String rpcUrl, String tokenAddress, String walletAddress) async {
  final rpcClient = RpcClient(rpcUrl);
  final walletPublicKey = Ed25519HDPublicKey.fromBase58(walletAddress);
  final tokenMintPublicKey = Ed25519HDPublicKey.fromBase58(tokenAddress);
  final pdaResult = await Ed25519HDPublicKey.findProgramAddress(
    seeds: [
      walletPublicKey.bytes,
      Ed25519HDPublicKey.fromBase58(TokenProgram.programId).bytes,
      tokenMintPublicKey.bytes,
    ],
    programId: Ed25519HDPublicKey.fromBase58(AssociatedTokenAccountProgram.programId),
  );
  final tokenAccountsResult = await rpcClient.getAccountInfo(pdaResult.toString(), encoding: Encoding.jsonParsed);
  if (tokenAccountsResult.value?.data != null) {
    final dataJson = tokenAccountsResult.value!.data!.toJson()['parsed'];
    final tokenAccountData = TokenAccountData.fromJson(dataJson as Map<String, dynamic>);
    return tokenAccountData.info.tokenAmount.uiAmountString ?? '0';
  }
  return '0';
}

Future<List<(String signature, String from, DateTime timestamp)>> getLatestSolanaTransactions(String rpcUrl) async {
  // final rpcClient = RpcClient(rpcUrl);
  // int currentSlot = await rpcClient.getSlot(commitment: Commitment.finalized);
  final List<(String, String, DateTime)> txs = [];
  // while (txs.length < 10 && currentSlot > 0) {
  //   final block = await rpcClient.getBlock(
  //     currentSlot,
  //     rewards: false,
  //     maxSupportedTransactionVersion: 0,
  //     commitment: Commitment.finalized,
  //   );
  //   if (block != null) {
  //     final blockTime = block.blockTime != null
  //         ? DateTime.fromMillisecondsSinceEpoch(block.blockTime! * 1000, isUtc: true)
  //         : DateTime.now().toUtc();
  //     for (final raw in block.transactions) {
  //       final ParsedTransaction(:message, :signatures) = ParsedTransaction.fromJson(raw.toJson());
  //       final sig = signatures.first;
  //       final from = message.accountKeys.first.pubkey;
  //       txs.add((sig, from, blockTime));
  //       if (txs.length == 10) break;
  //     }
  //   }
  //   currentSlot--;
  // }

  // final int latestSlot = await rpcClient.getSlot();
  // // 2. Get the block details for that slot, with transactions in 'jsonParsed' format
  // final block = await rpcClient.getBlock(
  //   latestSlot - 1000,
  //   commitment: Commitment.confirmed,
  //   transactionDetails: TransactionDetailLevel.full,
  //   encoding: Encoding.base64,
  //   maxSupportedTransactionVersion: 0,
  //   rewards: false,
  // );

  // if (block != null && block.transactions.isNotEmpty) {
  //   int count = 0;
  //   for (var raw in block.transactions) {
  //     if (count >= 10) break;
  //     final tx = ParsedTransaction.fromJson(raw.toJson());
  //     final message = tx.message;
  //     final blockTime = block.blockTime;
  //     if (blockTime != null) {
  //       final sender = message.accountKeys.first.pubkey;
  //       final dateTime = DateTime.fromMillisecondsSinceEpoch(blockTime * 1000);
  //       txs.add((tx.signatures.first, sender, dateTime));
  //       count++;
  //     }
  //   }
  // }

  return txs;
}
