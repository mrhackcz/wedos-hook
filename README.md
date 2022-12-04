# wedos-hook
`wedos-hook` is a shell script to integrate the [dehydrated ACME client](https://github.com/lukas2511/dehydrated) with Wedos DNS servers for dns-01 challenges. 

Connect the Wedos JSON WAPI with Let's Encrypt ACME dns-01 challenge via Dehydrated client to get certificate. Easy, using only bash shell and with few external dependecies.

Hook is configured for localy deploying certificates to $BASEDIR/certs, if you want to use your own deploy hook, add `WAPI_DEPLOY_CERT_HOOK="path/to/hook.sh"` to dehydrated config. You can configure exit_hook as well: `WAPI_EXIT_HOOK="path/to/exit_hook.sh"`

## Requirements
- [Wedos](https://wedos.com/) account with configured WAPI (more in Configuration)
- [dehydrated ACME client script]([https://github.com/lukas2511/dehydrated](https://github.com/dehydrated-io/dehydrated))
- [jq](https://stedolan.github.io/jq/)
- curl
- grep
- dig

## Configuration
Login to the wedos Customer administration, open Customer tab and click to WAPI interface. Activate WAPI, setup allowed IP adresses, choose password and save. Preferred protocol has to be JSON !

Download and [configure dehydrated per the documentation](https://github.com/dehydrated-io/dehydrated/blob/master/README.md#getting-started). And add to the config file following options:
- `CHALLENGETYPE="dns-01"`
- `HOOK="${BASEDIR}/wedos-hook.sh"`
- `WAPI_LOGIN="email"`
- `WAPI_PASS="xxxxxxxxxx"`
- `WAPI_URL="https://api.wedos.com/wapi/json" (optional)`
- `WAPI_WAIT=600 (optional, default 600)`

Download `wedos-hook.sh`, place it in the same location as dehydrated and make it executable.

That's all, finally you can run `dehydrated -c -f /etc/dehydrated/config`, add it to the crontab and get Let's Encrypt certificate with dns-01 challenge.
