# =============================================================================
  {% for line in fileBanner %}
# {{line}} {% endfor %}
# =============================================================================

# Tracking max IDs for all auto_increment columns.
55 8 * * * root /usr/local/ops/bin/tracking_max_id.sh --remote-host budbnew001.prod.euw2.ckint.io --remote-port 3301 --schema-name accessRequestId_0000,alchemy_id_0000,alchemy_target_0000,ayce_numericId_0000,ca_numericId_0000,cookieId_0000,ip_0000,lexisnexis_numericId_0000,numericId_0000,offers_contentId_0000,referenceId_0000,sms_numericId_0000,tuiis_numericId_0000 --days 180 --growth-pct 5 > /tmp/tracking_max_id_cron.log 2>&1
0 9 * * * root /usr/local/ops/bin/tracking_max_id.sh --remote-host budbnew009.prod.euw2.ckint.io --remote-port 3301 --schema-name ck --days 180 --growth-pct 5 > /tmp/tracking_max_id_cron.log 2>&1