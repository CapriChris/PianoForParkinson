import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../ui/qin_components.dart';
import '../app/page_title.dart';
import '../data/record_audit.dart';
import '../domain/contracts.dart';

class RecordHealthPage extends StatefulWidget {
  const RecordHealthPage({super.key, required this.c});
  final AppController c;
  @override
  State<RecordHealthPage> createState() => _RecordHealthPageState();
}

class _RecordHealthPageState extends State<RecordHealthPage> {
  late Future<Json> report;
  @override
  void initState() {
    super.initState();
    report = RecordAudit.run(
      widget.c.repository.safety,
      cancelled: () => !mounted,
    );
  }

  void reload() => setState(
    () => report = RecordAudit.run(
      widget.c.repository.safety,
      cancelled: () => !mounted,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Scaffold(
      appBar: AppBar(title: PageTitle(c.text('记录完整性检查', 'Record integrity'))),
      body: FutureBuilder<Json>(
        future: report,
        builder: (context, snapshot) => QinPageList(
          children: [
            QinSectionTitle(
              c.text('本机记录状态', 'Local record status'),
              subtitle: c.text(
                '只读取记录，不删除、修改或重新计算成绩。',
                'Reads records without deleting, modifying or recalculating scores.',
              ),
            ),
            if (snapshot.connectionState != ConnectionState.done)
              QinStatus(
                text: c.text('正在分批检查，请稍候…', 'Checking records in batches…'),
                child: const LinearProgressIndicator(),
              )
            else if (snapshot.hasError)
              QinStatus(
                tone: QinTone.error,
                text: c.text(
                  '暂时无法读取。原始记录和已有迁移备份会保留。',
                  'Unable to read records. Original data and existing migration backups are preserved.',
                ),
                child: OutlinedButton(
                  onPressed: reload,
                  child: Text(c.text('重试检查', 'Retry check')),
                ),
              )
            else ...[
              QinStatus(
                tone:
                    snapshot.data!['complete'] == true &&
                        snapshot.data!['issues'] == 0
                    ? QinTone.success
                    : QinTone.warning,
                text: snapshot.data!['complete'] != true
                    ? c.text('检查尚未全部完成', 'The check did not finish')
                    : snapshot.data!['issues'] == 0
                    ? c.text('检查完成，未发现异常', 'Check complete. No issues found')
                    : c.text(
                        '检查完成，发现需要关注的记录',
                        'Check complete. Some records need attention',
                      ),
              ),
              const SizedBox(height: 16),
              QinMetrics(
                values: [
                  QinMetric(
                    c.text('已检查记录', 'Records checked'),
                    '${snapshot.data!['checked']}',
                    icon: Icons.fact_check_outlined,
                  ),
                  QinMetric(
                    c.text('异常项目', 'Issues found'),
                    '${snapshot.data!['issues']}',
                    icon: Icons.report_outlined,
                  ),
                ],
              ),
              if (snapshot.data!['complete'] != true) ...[
                const SizedBox(height: 16),
                Text(
                  c.text(
                    '请保留本机数据后联系开发者处理。',
                    'Preserve device data and contact the developer.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: reload,
                child: Text(c.text('重新检查', 'Check again')),
              ),
              if (snapshot.data!['issues'] != 0) ...[
                const SizedBox(height: 16),
                ExpansionTile(
                  title: Text(c.text('查看检查详情', 'Check details')),
                  children: [
                    for (final line in snapshot.data!['details'] as List)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: SelectableText(
                          '$line',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
