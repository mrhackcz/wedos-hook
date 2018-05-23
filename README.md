# wedos-hook
`wedos-hook` is a shell script to integrate the [dehydrated ACME client](https://github.com/lukas2511/dehydrated) with Wedos DNS servers for dns-01 challenges. 

Connect the Wedos JSON WAPI with Let's Encrypt ACME dns-01 challenge via Dehydrated client to get certificate. Easy, using only bash shell and not a lot external dependecies.

Hook is configured for localy deploying certificates to $BASEDIR/certs, if you want to deploy certificates with rsync,ssh or another way, just edit `deploy_cert` function.

## Requirements
- [Wedos](https://hosting.wedos.com/) account with configured WAPI (more in Configuration)
- [dehydrated ACME client script](https://github.com/lukas2511/dehydrated)
- [jq](https://stedolan.github.io/jq/)
- curl
- grep
- dig

## Configuration
Download and [configure dehydrated per the documentation](https://github.com/lukas2511/dehydrated/blob/master/README.md#getting-started). And add to the config file following options:
- `CHALLENGETYPE="dns-01"`
- `HOOK="${BASEDIR}/wedos_api.sh"`

Login to the wedos Customer administration, open Customer tab and click to WAPI interface. Activate WAPI, setup allowed IP adresses and choose password, then save. Preferred protocol has to be JSON !

Download `wedos-hook` and place it in the same location as dehydrated. Open the script and change -
- `login="EMAIL LOGIN"`
- `wpass="P4SSW0RD"`

That's all, finally you can run `dehydrated -c -f /etc/dehydrated/config`, add it to the crontab and get Let's Encrypt certificate with dns-01 challenge.

## JSON ?
Yes, I know. Method used in the script to send "JSON" request to wedos WAPI is not a JSON. But thats not my fault, and it is Wedos's problem. If they said "send us a json request" it means - "Send us a plaintext request, where you fill a json to the 'request' variable". :--)) Hosting masters.
