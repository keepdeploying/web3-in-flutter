/// The chain families Flutter Counter supports.
///
/// Networks in the same family share how keys, addresses, signatures and
/// transactions work. All four EVM networks are one family: one key, one
/// address, one counter contract.
enum ChainFamily {
  evm('EVM'),
  solana('Solana'),
  sui('Sui'),
  cosmos('Cosmos'),
  near('NEAR');

  const ChainFamily(this.label);

  /// A short name to show in the UI.
  final String label;
}
