#!/bin/bash
while read dip_id; do
    ead=$(bundle exec ruby exe/get_ead.rb /opt/shares/library_dips_1/$(xtpath $dip_id)/data/mets.xml 2>/dev/null)
    echo $dip_id
    bundle exec ruby exe/fail_if.rb --identifier "$dip_id" --ead "/opt/shares/library_dips_1/$(xtpath $dip_id)/$ead" --xml xml2 2>&1 | grep -v pairtree
done
