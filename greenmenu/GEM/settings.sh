#!/bin/sh
CMD=$1; ARG1=$2; ARG2=$3
. /fs/sda0/ClusterMap/GEM/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
# Map size and safe area from the green menu, without editing files by hand.
#
#   settings.sh show
#   settings.sh dpi +5|-5|<value>
#   settings.sh inset top|bottom|left|right +5|-5|<value>
#   settings.sh preset <dpi> <top>,<bottom>,<left>,<right>
#
# Changes the unit's copy of the settings (the one the hook reads at boot when
# no card root holds a gal_dualscreen.conf), the card's ClusterMap copy (so a
# later install keeps the values) and any gal_dualscreen.conf at a card root
# (which the hook would read first). The installer's own lines in the unit's
# copy (GAL_PLAYER_WINDOW, GAL_SECONDARY_MARGINS) are kept.
APP_MOUNT=/mnt/app
UNIT_DIR=$APP_MOUNT/eso/lib/gal_dualscreen
UNIT_CONF=$UNIT_DIR/gal_dualscreen.conf
CARD_CONF=$PKG/gal_dualscreen.conf
CONFIG=/mnt/system/etc/eso/production/smartphone_integrator.json
CARPLAY_SAFEAREA=$APP_MOUNT/root/mibr-carplay111-safearea.conf
# The hook's built-in values, used when a file has no line for the key.
DEFAULT_DPI=140
DEFAULT_INSETS=40,40,127,127
DPI_MIN=60
DPI_MAX=320
INSET_MAX=127

# The value of KEY in FILE. The hook keeps the first line for a key.
conf_get()
{
    sed -n "s/^$1=\([^ 	]*\)[ 	]*$/\1/p" "$2" 2>/dev/null | head -1
}

# Sets KEY=VALUE in FILE through a new file and a rename: every existing line
# for the key is replaced, or the line is appended when there is none.
conf_set()
{
    if grep -q "^$1=" "$3" 2>/dev/null; then
        sed "s/^$1=.*/$1=$2/" "$3" > "$3.new" || { rm -f "$3.new"; return 1; }
    else
        { cat "$3"; echo "$1=$2"; } > "$3.new" || { rm -f "$3.new"; return 1; }
    fi
    # The per-side keys win over GAL_SECONDARY_INSETS in the hook; comment them out.
    if [ "$1" = GAL_SECONDARY_INSETS ]; then
        sed 's/^\(GAL_SECONDARY_INSETS_[A-Z]*=\)/#\1/' "$3.new" > "$3.new2" && mv "$3.new2" "$3.new" || { rm -f "$3.new" "$3.new2"; return 1; }
    fi
    chmod 644 "$3.new" 2>/dev/null
    mv "$3.new" "$3"
}

# The file the current values are read from: the one the hook reads.
SOURCE=
for f in /fs/sdb0/gal_dualscreen.conf /fs/sda0/gal_dualscreen.conf "$UNIT_CONF" "$CARD_CONF"; do
    if [ -r "$f" ]; then SOURCE=$f; break; fi
done
DPI=`[ -n "$SOURCE" ] && conf_get GAL_SECONDARY_DPI "$SOURCE"`
INSETS=`[ -n "$SOURCE" ] && conf_get GAL_SECONDARY_INSETS "$SOURCE"`
case "$DPI" in ''|*[!0-9]*) DPI=$DEFAULT_DPI ;; esac
case "$INSETS" in
    [0-9]*,[0-9]*,[0-9]*,[0-9]*) ;;
    *) INSETS=$DEFAULT_INSETS ;;
esac
OLD_IFS=$IFS; IFS=,; set -- $INSETS; IFS=$OLD_IFS
TOP=$1; BOTTOM=$2; LEFT=$3; RIGHT=$4
OLD_DPI=$DPI; OLD_INSETS=$TOP,$BOTTOM,$LEFT,$RIGHT

# The hook's log of this boot, wherever it landed.
HOOK_LOG=
for f in /tmp/gal_dualscreen.log /fs/sda0/logs/gal_dualscreen.log /fs/sdb0/logs/gal_dualscreen.log; do
    if [ -r "$f" ]; then HOOK_LOG=$f; break; fi
done

show()
{
    echo "Settings file in use: ${SOURCE:-none, built-in defaults}"
    echo "  DPI: $DPI (lower draws the map smaller)"
    echo "  Insets top,bottom,left,right: $TOP,$BOTTOM,$LEFT,$RIGHT (each 0 to $INSET_MAX)"
    # The start-up environment wins over the file.
    e=`sed -n 's/.*"GAL_SECONDARY_DPI=\([0-9]*\)".*/\1/p' "$CONFIG" 2>/dev/null | head -1`
    [ -n "$e" ] && echo "  DPI $e is set by the installed start-up and wins over the file"
    # Other copies, when they hold different values.
    for f in "$UNIT_CONF" "$CARD_CONF"; do
        [ -r "$f" ] && [ "$f" != "$SOURCE" ] || continue
        d=`conf_get GAL_SECONDARY_DPI "$f"`; i=`conf_get GAL_SECONDARY_INSETS "$f"`
        [ "$d,$i" = "$DPI,$INSETS" ] || echo "Other copy $f: DPI ${d:-unset}, insets ${i:-unset}"
    done
    # What the hook loaded at boot and sent to the phone, from its log.
    if [ -n "$HOOK_LOG" ]; then
        p=`sed -n 's/.*event=config.file result=loaded path=\([^ ]*\).*/\1/p' "$HOOK_LOG" | tail -1`
        d=`sed -n 's/.*event=secondary.video_config result=success.* dpi=\([0-9]*\).*/\1/p' "$HOOK_LOG" | tail -1`
        i=`sed -n 's/.*event=video.insets result=success.* top=\([0-9]*\) bottom=\([0-9]*\) left=\([0-9]*\) right=\([0-9]*\).*/\1,\2,\3,\4/p' "$HOOK_LOG" | tail -1`
        echo "Running since boot (hook log):"
        echo "  file loaded: ${p:-not logged}"
        echo "  DPI: ${d:-not sent yet (connect the phone)}"
        echo "  insets: ${i:-not sent yet (connect the phone)}"
    else
        echo "Running since boot: no hook log (map not installed, or no reboot yet)"
    fi
}

# A new value from the current one and +N, -N or N, clamped to MIN..MAX.
# Anything else keeps the current value.
adjust()
{
    case "$2" in
        *[!0-9+-]*|'') v=$1 ;;
        +[0-9]*) v=`expr $1 + ${2#+}` ;;
        -[0-9]*) v=`expr $1 - ${2#-}` ;;
        [0-9]*)  v=$2 ;;
        *) v=$1 ;;
    esac
    case "$v" in -*) v=0 ;; esac
    [ "$v" -lt "$3" ] && v=$3
    [ "$v" -gt "$4" ] && v=$4
    echo $v
}

echo "Phone map on the digital cluster: settings"
case "$CMD" in
    show|'')
        show
        exit 0 ;;
    dpi)
        DPI=`adjust $DPI "$ARG1" $DPI_MIN $DPI_MAX` ;;
    inset)
        case "$ARG1" in
            top)    TOP=`adjust $TOP "$ARG2" 0 $INSET_MAX` ;;
            bottom) BOTTOM=`adjust $BOTTOM "$ARG2" 0 $INSET_MAX` ;;
            left)   LEFT=`adjust $LEFT "$ARG2" 0 $INSET_MAX` ;;
            right)  RIGHT=`adjust $RIGHT "$ARG2" 0 $INSET_MAX` ;;
            *) echo "Unknown side: $ARG1"; exit 0 ;;
        esac ;;
    preset)
        DPI=`adjust $DPI "$ARG1" $DPI_MIN $DPI_MAX`
        OLD_IFS=$IFS; IFS=,; set -- $ARG2; IFS=$OLD_IFS
        TOP=`adjust $TOP "$1" 0 $INSET_MAX`; BOTTOM=`adjust $BOTTOM "$2" 0 $INSET_MAX`
        LEFT=`adjust $LEFT "$3" 0 $INSET_MAX`; RIGHT=`adjust $RIGHT "$4" 0 $INSET_MAX` ;;
    *)
        echo "Unknown command: $CMD"
        exit 0 ;;
esac
INSETS=$TOP,$BOTTOM,$LEFT,$RIGHT

RC=0
apply()
{
    conf_set GAL_SECONDARY_DPI $DPI "$1" && conf_set GAL_SECONDARY_INSETS $INSETS "$1"
}

# The card: the ClusterMap copy, and any copy at a card root.
for f in "$CARD_CONF" /fs/sda0/gal_dualscreen.conf /fs/sdb0/gal_dualscreen.conf; do
    [ -f "$f" ] || continue
    if apply "$f"; then echo "Saved to $f"; else echo "Could not write $f"; RC=1; fi
done

# The unit's copy, which needs /mnt/app writable for a moment.
if [ -f "$UNIT_CONF" ]; then
    if mount -uw $APP_MOUNT 2>/dev/null && apply "$UNIT_CONF"; then
        echo "Saved to the unit: $UNIT_CONF"
        # CarPlay's safe area comes from the same insets; recompute it as the
        # installer does, from the window and margins it recorded.
        if [ -f "$CARPLAY_SAFEAREA" ]; then
            W=`conf_get GAL_PLAYER_WINDOW "$UNIT_CONF"`
            M=`conf_get GAL_SECONDARY_MARGINS "$UNIT_CONF"`
            MAP_W=`echo "$W" | sed -n 's/^\([0-9][0-9]*\)x[0-9][0-9]*$/\1/p'`
            MAP_H=`echo "$W" | sed -n 's/^[0-9][0-9]*x\([0-9][0-9]*\)$/\1/p'`
            MARGIN_W=`echo "$M" | sed -n 's/^\([0-9][0-9]*\)x[0-9][0-9]*$/\1/p'`
            MARGIN_H=`echo "$M" | sed -n 's/^[0-9][0-9]*x\([0-9][0-9]*\)$/\1/p'`
            if [ -n "$MAP_W" ] && [ -n "$MAP_H" ] && [ -n "$MARGIN_W" ] && [ -n "$MARGIN_H" ]; then
                # "|| :" because expr exits 1 when the answer is 0.
                SAFE_Y=`expr $TOP \* $MAP_H / \( 480 - $MARGIN_H \) || :`
                SAFE_B=`expr $BOTTOM \* $MAP_H / \( 480 - $MARGIN_H \) || :`
                SAFE_X=`expr $LEFT \* $MAP_W / \( 800 - $MARGIN_W \) || :`
                SAFE_R=`expr $RIGHT \* $MAP_W / \( 800 - $MARGIN_W \) || :`
                SAFE_W=`expr $MAP_W - $SAFE_X - $SAFE_R || :`
                SAFE_H=`expr $MAP_H - $SAFE_Y - $SAFE_B || :`
                if [ "$SAFE_W" -ge 160 ] && [ "$SAFE_H" -ge 120 ] &&
                   printf 'x=%s\ny=%s\nw=%s\nh=%s\n' $SAFE_X $SAFE_Y $SAFE_W $SAFE_H > "$CARPLAY_SAFEAREA"; then
                    echo "CarPlay map: safe area ${SAFE_W}x${SAFE_H} at ${SAFE_X},${SAFE_Y}"
                else
                    echo "CarPlay map: these insets leave too little of the window; safe area unchanged"
                fi
            fi
        fi
    else
        echo "Could not write the unit's copy: $UNIT_CONF"
        RC=1
    fi
    mount -ur $APP_MOUNT 2>/dev/null
else
    echo "The cluster map is not installed yet: Install takes these values to the unit."
fi

# Things that would override the file.
grep -q '"GAL_SECONDARY_DPI=' "$CONFIG" 2>/dev/null && \
    echo "NOTE: the installed start-up sets the DPI itself (enable_hook.sh --dpi), which wins over this file. Install again from the menu to drop it."
grep -q '^GAL_SECONDARY_UI_CONFIG_HEX=' "$UNIT_CONF" "$CARD_CONF" 2>/dev/null && \
    echo "NOTE: GAL_SECONDARY_UI_CONFIG_HEX is set and replaces the insets. Comment it out in gal_dualscreen.conf."

echo
echo "Changed: DPI $OLD_DPI -> $DPI, insets $OLD_INSETS -> $INSETS"
show
echo
if [ $RC -eq 0 ]; then
    echo "CLUSTERMAP_SETTINGS_OK"
    echo "Hold the power button for 10 seconds to reboot the unit and apply them."
else
    echo "CLUSTERMAP_SETTINGS_FAILED. Read the messages above."
fi
exit 0
