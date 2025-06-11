# SUI Coin Flip Migration System

This directory contains scripts for migrating treasury funds and configuration settings after package upgrades.

## Overview

When you upgrade your SUI package, the old contract continues to exist with its treasury funds and configuration settings. This migration system allows you to transfer:

- **Treasury funds** from old GameConfig to new GameConfig
- **Configuration settings** (fee percentage, bet limits, pause state)
- **Complete migration** of everything at once

## Available Scripts

### 1. `check_old_configs.sh`
**Purpose**: Check what needs to be migrated  
**Usage**: `make check-old-configs NETWORK=testnet`

This script analyzes your upgrade history and shows:
- Current contract state
- All previous package versions
- Treasury funds available for migration
- Configuration differences that need syncing
- Migration opportunities

### 2. `migrate_treasury.sh`
**Purpose**: Migrate treasury funds only  
**Usage**: `make migrate-treasury NETWORK=testnet`

This script:
- Finds the most recent upgrade
- Checks old treasury balance
- Transfers all funds to new treasury
- Updates tracking in config.json
- Verifies successful migration

### 3. `migrate_config.sh`  
**Purpose**: Migrate configuration settings only  
**Usage**: `make migrate-config NETWORK=testnet`

This script:
- Compares old vs new configuration
- Updates fee percentage if different
- Updates bet limits if different  
- Updates pause state if different
- Records migration history

### 4. `migrate_all.sh`
**Purpose**: Complete migration (treasury + config)  
**Usage**: `make migrate-all NETWORK=testnet`

This script:
- Runs treasury migration first
- Then runs configuration migration
- Provides complete verification
- Records full migration history

## Typical Workflow

### After Package Upgrade

1. **Check what needs migration**:
   ```bash
   make check-old-configs NETWORK=testnet
   ```

2. **Migrate everything** (recommended):
   ```bash
   make migrate-all NETWORK=testnet
   ```

   Or migrate separately:
   ```bash
   make migrate-treasury NETWORK=testnet
   make migrate-config NETWORK=testnet
   ```

### Example Output

```
Migration opportunities found:
  💰 Total treasury funds in old configs: 0.025 SUI

Available Migration Commands:
  make migrate-treasury NETWORK=testnet    - Migrate treasury funds
  make migrate-config NETWORK=testnet      - Migrate configuration settings  
  make migrate-all NETWORK=testnet         - Migrate everything at once

Recommendation: Run 'make migrate-all NETWORK=testnet' to migrate everything
```

## Migration Tracking

All migrations are tracked in your `deployments/<network>/config.json`:

```json
{
  "lastTreasuryMigration": {
    "transaction": "TxHash123...",
    "date": "2025-06-11T02:30:00Z",
    "migratedAmount": "25000000",
    "migratedAmountSUI": 0.025
  },
  "lastConfigMigration": {
    "date": "2025-06-11T02:31:00Z", 
    "migratedSettings": {
      "feePercentage": {"from": "300", "to": "250"},
      "minBetAmount": {"from": "5000000", "to": "10000000"}
    }
  },
  "lastCompleteMigration": {
    "date": "2025-06-11T02:31:00Z",
    "treasuryMigrated": true,
    "configMigrated": true
  }
}
```

## Safety Features

### Confirmation Prompts
All migration scripts require explicit confirmation:
```
WARNING: This will migrate all treasury funds from old to new contract!
Are you sure you want to continue? (yes/no)
```

### Transaction Verification
Every migration:
- Checks transaction success status
- Verifies final balances
- Records transaction hashes
- Updates tracking automatically

### Rollback Information
If needed, you can access:
- Complete upgrade history
- All old AdminCaps and GameConfigs
- Transaction hashes for audit trail

## Troubleshooting

### "No upgrades found"
This means you haven't upgraded your package yet. No migration needed.

### "Configuration not accessible"  
The old GameConfig may have been deleted or treasury already migrated.

### "AdminCap not accessible"
The old AdminCap may have been transferred or deleted.

### "Transaction failed"
Check:
- Gas budget is sufficient (200M MIST recommended)
- You own the required AdminCaps
- Network connectivity

## Security Considerations

### Admin Access Required
- You must own both old and new AdminCaps
- Scripts verify AdminCap ownership automatically
- Only admin can execute migration functions

### One-Way Migration
- Treasury migration is one-way (old → new)
- Keep backups of old AdminCaps if needed
- Migration history is permanently recorded

### Verification
- Always run `check-old-configs` first
- Verify migration results after completion
- Monitor contract state for correctness

## Integration with Upgrade Process

The migration system integrates with your existing upgrade workflow:

1. **Upgrade**: `make upgrade NETWORK=testnet`
2. **Check**: `make check-old-configs NETWORK=testnet`  
3. **Migrate**: `make migrate-all NETWORK=testnet`
4. **Verify**: `make status NETWORK=testnet`

## Advanced Usage

### Manual Migration
If you need fine-grained control, you can call the scripts directly:

```bash
./scripts/migrate/migrate_treasury.sh testnet https://fullnode.testnet.sui.io:443 200000000
```

### Selective Migration
You can migrate from specific upgrades by modifying the scripts to target particular old configs.

### Batch Migration
For multiple networks, create a batch script:

```bash
for network in testnet mainnet; do
  make migrate-all NETWORK=$network
done
```

## Support

If you encounter issues:

1. Check the transaction output for error details
2. Verify object IDs in `deployments/<network>/config.json`
3. Ensure sufficient SUI balance for gas
4. Confirm AdminCap ownership

For additional help, check the main project documentation or open an issue. 