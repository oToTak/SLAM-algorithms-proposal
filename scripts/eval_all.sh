SUMMARY_FILE="results/summary.csv"
echo "method,mode,dataset,seq,run,ate_rmse_m,rpe_trans_m,coverage,tracking_lost,commit" > $SUMMARY_FILE

for traj in results/*/*/*/*/traj_run*.txt; do
    [ -e "$traj" ] || continue

    DIR=$(dirname "$traj")
    META="$DIR/meta.yaml"
    
    method=$(awk '/^method:/ {print $2}' "$META")
    mode=$(awk '/^mode:/ {print $2}' "$META")
    dataset=$(awk '/^dataset:/ {print $2}' "$META")
    seq=$(awk '/^seq:/ {print $2}' "$META")
    run=$(awk '/^run:/ {print $2}' "$META")
    coverage=$(awk '/^coverage:/ {print $2}' "$META")
    tracking_lost=$(awk '/^tracking_lost:/ {print $2}' "$META")
    commit=$(awk '/^commit:/ {print $2}' "$META")

    if [ "$dataset" == "ucu" ]; then
        gt="data/ucu_tum/$seq/groundtruth.txt"
    else
        gt="data/$dataset/$seq/groundtruth.txt"
    fi

    align_flag="-a"
    [ "$mode" == "mono" ] && align_flag="-as"

    ate_rmse_m=""
    if [ "$tracking_lost" == "false" ] && [ -f "$gt" ]; then
        ate_rmse_m=$(evo_ape tum "$gt" "$traj" $align_flag --t_max_diff 0.02 --save_results "$DIR/ape_run${run}.zip" | awk '/rmse/ {print $2}')
    fi

    echo "$method,$mode,$dataset,$seq,$run,$ate_rmse_m,,$coverage,$tracking_lost,$commit" >> $SUMMARY_FILE
    echo "Оброблено: $traj (RMSE: $ate_rmse_m)"
done

echo "Файл $SUMMARY_FILE оновлено."