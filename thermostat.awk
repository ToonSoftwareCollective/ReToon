# config_happ_thermstat.xml of the original software -> ReToon's
# thermostat.json: the four preset temperatures and the week program.
# Original: states 0 comfort, 1 home, 2 sleep, 3 away, 4 holiday (as away
# here), temperatures in hundredths; days 0 = Sunday. ReToon: Monday first.
BEGIN { RS = "<"; n = 0 }
{ split($0, a, ">"); tag = a[1]; val = a[2]; sub(/[ \t\r\n]+$/, "", val) }
tag == "id" { id = val }
tag == "tempValue" { temp[id] = val / 100 }
tag == "programState" { prog = val }
tag == "entry" || substr(tag, 1, 6) == "entry " { n++ }
tag == "startDayOfWeek" { sd[n] = val + 0 }
tag == "startHour" { sh[n] = val + 0 }
tag == "startMin" { sm[n] = val + 0 }
tag == "targetState" { ts[n] = val + 0 }
END {
	name[0] = "comfort"; name[1] = "home"; name[2] = "sleep"; name[3] = "away"; name[4] = "away"
	if (!(0 in temp)) exit 1
	printf "{\"presets\":{\"comfort\":%s,\"home\":%s,\"sleep\":%s,\"away\":%s},\n", temp[0], temp[1], temp[2], temp[3]
	printf "\"program_enabled\":%s,\n\"program\":[", (prog != "" && prog != 0 && n > 0) ? "true" : "false"
	for (d = 0; d < 7; d++) {
		vd = (d + 1) % 7; k = 0
		for (i = 1; i <= n; i++)
			if (sd[i] == vd && ts[i] >= 0 && ts[i] <= 4) { k++; at[k] = sh[i] * 60 + sm[i]; st[k] = ts[i] }
		for (i = 2; i <= k; i++)
			for (j = i; j > 1 && at[j] < at[j - 1]; j--) {
				t = at[j]; at[j] = at[j - 1]; at[j - 1] = t
				t = st[j]; st[j] = st[j - 1]; st[j - 1] = t
			}
		printf "%s[", (d ? ",\n" : "\n")
		for (i = 1; i <= k; i++)
			printf "%s[\"%02d:%02d\",\"%s\"]", (i > 1 ? "," : ""), int(at[i] / 60), at[i] % 60, name[st[i]]
		printf "]"
	}
	printf "]}\n"
}
