#!/usr/bin/env bash
. utils.bash
shopt -s lastpipe 


# shellcheck disable=SC2329
sum_bytes() {
   local total=0
   for size in "$@"; do
      local num="${size//[^0-9.]/}"
      local unit="${size//[0-9.]/}"
      case "$unit" in
         B|'') mult=1 ;;
         K|Ki|KB|KiB) mult=1024 ;;
         M|Mi|MB|MiB) mult=1048576 ;;
         G|Gi|GB|GiB) mult=1073741824 ;;
         T|Ti|TB|TiB) mult=1099511627776 ;;
      esac
      # dc: scale for decimals, multiply, add to total
      total=$(echo "2 k $total $num $mult * + p" | dc)
      ## dc is a reverse Polish notation (RPN) calculator that uses a stack. Here's what each part does:
      ## | 2 k    | Set precision to 2 decimal places          | Sets scale           |
      ## | $total | Push current total onto stack              | [total]              | 
      ## | $num   | Push number (e.g., 95.15) onto stack       | [total, num]         | 
      ## | $mult  | Push multiplier (e.g., 1073741824 for GiB) | [total, num, mult]   | 
      ## | *      | Multiply top two stack items               | [total, num*mult]    |
      ## | +      | Add top two stack items                    | [total + (num*mult)] | 
      ## | p      | Print top of stack                         | Outputs result       |
   done
   # Convert to best unit
   if (( $(echo "$total 1099511627776 >=" | bc -l) )); then
      echo "scale=2; $total / 1099511627776" | bc | xargs printf "%.2fTiB\n"
   elif (( $(echo "$total 1073741824 >=" | bc -l) )); then
      echo "scale=2; $total / 1073741824" | bc | xargs printf "%.2fGiB\n"
   elif (( $(echo "$total 1048576 >=" | bc -l) )); then
      echo "scale=2; $total / 1048576" | bc | xargs printf "%.2fMiB\n"
   elif (( $(echo "$total 1024 >=" | bc -l) )); then
      echo "scale=2; $total / 1024" | bc | xargs printf "%.2fKiB\n"
   else
      printf "%.0fB\n" "$total"
   fi
}

# shellcheck disable=SC2329
sum_bytes2() {
    perl -e '
        my $total = 0;
        foreach (@ARGV) {
            /^([\d\.]+)(.*)$/;
            my ($num, $unit) = ($1, $2);
            my %mult = ( B=>1, KiB=>1024, MiB=>1024**2, GiB=>1024**3, TiB=>1024**4,
                               KB=>1000,  MB=>1000**2,  GB=>1000**3,  TB=>1000**4);
            $total += $num * ($mult{$unit} // 1);
        }
        if ($total >= 1024**4) { printf "%.2fTiB\n", $total/1024**4 }
        elsif ($total >= 1024**3) { printf "%.2fGiB\n", $total/1024**3 }
        elsif ($total >= 1024**2) { printf "%.2fMiB\n", $total/1024**2 }
        elsif ($total >= 1024) { printf "%.2fKiB\n", $total/1024 }
        else { printf "%.0fB\n", $total }
    ' "$@"
}

sum_bytes2 95.15GiB 14.5KB 12222MiB 13B
# sum_bytes 95.15GiB 14.5KB 122MiB 13B

exit

sqlite3 temp.db3 <<END
   create table subvolumes (
      main_mount_path,
      id INTEGER UNIQUE, 
      gen INTEGER,
      ogen INTEGER,
      parent INTEGER,
      top_level INTEGER,
      parent_uuid,
      received_uuid,
      uuid UNIQUE PRIMARY KEY,
      path UNIQUE,
      ro BOOLEAN,
      size
   );
   
   CREATE TEMP TABLE column_list AS
   SELECT GROUP_CONCAT(name, ', ') AS columns
   FROM pragma_table_info('subvolumes')
   WHERE name <> 'main_mount_path';
   
   CREATE OR REPLACE VIEW src_subvolumes AS 
   SELECT 
      id, 
      gen, 
      ogen, 
      parent, 
      top_level, 
      parent_uuid, 
      received_uuid, 
      uuid, 
      path, 
      ro, 
      size
   FROM subvolumes
   WHERE
      main_mount_path = 'src' OR 
      main_mount_path LIKE 'src/%';

   CREATE OR REPLACE VIEW dst_subvolumes AS 
   SELECT 
      id, 
      gen, 
      ogen, 
      parent, 
      top_level, 
      parent_uuid, 
      received_uuid, 
      uuid, 
      path, 
      ro, 
      size
   FROM subvolumes
   WHERE
      main_mount_path = 'dst' OR 
      main_mount_path LIKE 'dst/%';
END