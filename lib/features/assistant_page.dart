import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../app/page_title.dart';
import '../app/piano_app.dart' show ResultPage;
import '../domain/cognitive_tasks.dart';
import '../domain/contracts.dart';
import '../platform/assistant_gateway.dart';
import '../ui/qin_components.dart';
import '../ui/qin_page_background.dart';
import '../ui/qin_press.dart';
import '../ui/qin_theme.dart';
import 'assistant_context.dart';

Future<bool?> _askRecordConsent(
  BuildContext context,
  AppController c,
) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(c.text('结合训练记录？', 'Use practice records?')),
    content: Text(
      c.assistant.available
          ? c.text(
              '允许后，助手可在回答需要时查询你的训练记录，并将相关记录、指标和本会话内容发送给琴伴服务及${_provider(c)}，用于回答问题。聊天保存在本机，你可以删除会话或在设置中撤回记录授权。',
              'If you allow this, Piano Companion and ${_provider(c)} receive relevant practice records, metrics and conversation messages when needed. Chats are stored on this device. You can delete chats or revoke record access in Settings.',
            )
          : c.text(
              '在本机读取相关练习摘要并展示参考记录。目前未配置在线服务。',
              'Read relevant summaries on this device and show the records used. The online service is currently unconfigured.',
            ),
    ),
    actions: [
      QinTextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text(c.text('仅提问', 'Question only')),
      ),
      QinFilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: Text(c.text('允许结合记录', 'Allow records')),
      ),
    ],
  ),
);

String _provider(AppController c) => AssistantGateway.providerName.isEmpty
    ? c.text('模型服务商', 'its model provider')
    : AssistantGateway.providerName;

class AssistantReviewCard extends StatelessWidget {
  const AssistantReviewCard({
    super.key,
    required this.c,
    required this.recordId,
    required this.title,
    this.date,
  });

  final AppController c;
  final String recordId, title;
  final String? date;

  @override
  Widget build(BuildContext context) => QinInkWell(
    key: const ValueKey('assistant-review'),
    surfaceBuilder: (surface) => Card(child: surface),
    borderRadius: BorderRadius.circular(18),
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AssistantPage(
          c: c,
          recordId: recordId,
          recordLabel: date == null
              ? '${c.text('本次练习', 'This practice')} · $title'
              : '$date · $title',
        ),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: CircleAvatar(
              radius: 24,
              backgroundColor: context.qin.soft,
              foregroundColor: context.qin.primary,
              child: const Icon(Icons.auto_awesome_outlined),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.text('AI助手分析', 'AI assistant analysis'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  c.text('点评练习，指导练习', 'Practice review and guidance'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          QinCircleArrow(radius: 18, outlineColor: context.qin.primary),
        ],
      ),
    ),
  );
}

class AssistantPrivacyTile extends StatelessWidget {
  const AssistantPrivacyTile({
    super.key,
    required this.c,
    this.showDescription = true,
  });
  final AppController c;
  final bool showDescription;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(c.text('AI 结合训练记录', 'AI access to practice records')),
    subtitle: showDescription
        ? Text(
            c.text(
              '允许助手按问题查询训练记录，可随时撤回。',
              'Allow record queries when needed. You can revoke access anytime.',
            ),
          )
        : null,
    value: c.assistantRecordsAllowed,
    onChanged: (enabled) async {
      if (enabled && await _askRecordConsent(context, c) != true) return;
      if (!context.mounted) return;
      await _changeConsent(context, c, enabled);
    },
  );
}

Future<bool> _changeConsent(
  BuildContext context,
  AppController c,
  bool enabled,
) async {
  try {
    await c.setAssistantRecordsAllowed(enabled);
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(c.text('暂时无法保存设置。', 'Unable to save this setting.')),
        ),
      );
    }
    return false;
  }
}

class AssistantPage extends StatefulWidget {
  const AssistantPage({
    super.key,
    required this.c,
    this.recordId,
    this.recordLabel,
  });
  final AppController c;
  final String? recordId, recordLabel;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantTurn {
  const _AssistantTurn(
    this.question,
    this.scope,
    this.recordId,
    this.reply, {
    this.context,
    this.local = false,
    this.error,
    this.consentRevision,
    this.consentKey,
  });
  final String question;
  final AssistantScope scope;
  final String? recordId, error;
  final AssistantReply? reply;
  final AssistantContext? context;
  final int? consentRevision;
  final bool local;
  final String? consentKey;

  Json toJson() => {
    'question': question,
    'scope': scope.name,
    'record_id': recordId,
    'reply': reply == null
        ? null
        : {
            'answer': reply!.answer,
            'next_step': reply!.nextStep,
            'references': [
              for (final entry in reply!.references.entries)
                {'ref': entry.key, 'metrics': entry.value.toList()},
            ],
          },
    'context': context?.toStoredJson(),
    'local': local,
    'error': error,
    'consent_key': consentKey,
  };

  factory _AssistantTurn.fromJson(Json row) {
    final context = row['context'] == null
        ? null
        : AssistantContext.fromStoredJson(
            Map<String, dynamic>.from(row['context'] as Map),
          );
    return _AssistantTurn(
      row['question'] as String,
      AssistantScope.values.byName(row['scope'] as String),
      row['record_id'] as String?,
      row['reply'] == null
          ? null
          : AssistantReply.parse(
              Map<String, dynamic>.from(row['reply'] as Map),
              context?.toJson(),
            ),
      context: context,
      local: row['local'] == true,
      error: row['error'] as String?,
      consentKey: row['consent_key'] as String?,
    );
  }
}

class _AssistantPageState extends State<AssistantPage> {
  AppController get c => widget.c;
  late final _reader = AssistantContextReader(c);
  late String? _recordId = widget.recordId;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _turns = <_AssistantTurn>[];
  String? _pending;
  String _streamedAnswer = '';
  bool _busy = false;
  bool _loading = true;
  bool _switching = false;
  final _scaffold = GlobalKey<ScaffoldState>();
  List<Json> _conversations = [];
  String _conversationId = uuid();
  String? _conversationTitle;
  late String? _recordLabel = widget.recordLabel;
  Timer? _draftTimer;
  Future<void> _saveTail = Future.value();

  String get _profileId => c.repository.profile['profile_id'] as String;

  @override
  void initState() {
    super.initState();
    unawaited(_loadConversations());
  }

  Future<void> _loadConversations() async {
    try {
      final rows = await c.assistantConversations.list(_profileId);
      if (mounted) setState(() => _conversations = rows);
    } catch (_) {
      _storageNotice();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _storageNotice() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            c.text(
              '暂时无法保存或读取聊天记录，请重试。',
              'Chat history could not be saved or read. Please retry.',
            ),
          ),
        ),
      );
    });
  }

  Future<void> _persist() async {
    _draftTimer?.cancel();
    if (_turns.isEmpty && _pending == null && _input.text.trim().isEmpty) {
      return;
    }
    final first =
        _turns.firstOrNull?.question ?? _pending ?? _input.text.trim();
    final snapshot = <String, dynamic>{
      'id': _conversationId,
      'profile_id': _profileId,
      'title': _conversationTitle ?? first.characters.take(40).toString(),
      'updated_ms': DateTime.now().millisecondsSinceEpoch,
      'record_id': _recordId,
      'record_label': _recordLabel,
      'turns': [for (final turn in _turns) turn.toJson()],
      'draft': _input.text,
      'pending': _pending,
    };
    final write = c.assistantConversations.save(snapshot);
    _saveTail = write;
    try {
      await write;
      final rows = await c.assistantConversations.list(
        snapshot['profile_id'] as String,
      );
      if (mounted) setState(() => _conversations = rows);
    } catch (_) {
      _storageNotice();
    }
  }

  Future<void> _newConversation() async {
    if (_busy || _loading || _switching) return;
    setState(() => _switching = true);
    try {
      await _persist();
      if (!mounted) return;
      setState(() {
        _conversationId = uuid();
        _conversationTitle = null;
        _turns.clear();
        _input.clear();
        _recordId = null;
        _recordLabel = null;
      });
      _scaffold.currentState?.closeDrawer();
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _selectConversation(Json row) async {
    if (_busy || _loading || _switching) return;
    if (row['id'] == _conversationId) {
      _scaffold.currentState?.closeDrawer();
      return;
    }
    setState(() => _switching = true);
    try {
      await _persist();
      if (!mounted) return;
      final turns = [
        for (final turn in row['turns'] as List)
          _AssistantTurn.fromJson(Map<String, dynamic>.from(turn as Map)),
      ];
      final pending = row['pending'] as String?;
      if (pending != null) {
        turns.add(
          _AssistantTurn(
            pending,
            AssistantScope.automatic,
            row['record_id'] as String?,
            null,
            error: 'interrupted',
          ),
        );
      }
      setState(() {
        _conversationId = row['id'] as String;
        _conversationTitle = row['title'] as String;
        _recordId = row['record_id'] as String?;
        _recordLabel = row['record_label'] as String?;
        _turns
          ..clear()
          ..addAll(turns);
        _input.text = row['draft'] as String? ?? '';
      });
      _scaffold.currentState?.closeDrawer();
      _showLatest();
    } catch (_) {
      _storageNotice();
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _deleteConversation(Json row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(c.text('删除这段对话？', 'Delete this conversation?')),
        content: Text(
          c.text(
            '本机保存的消息和参考依据将一并删除。',
            'Saved messages and references on this device will be deleted.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(c.text('取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(c.text('删除', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy) return;
    _draftTimer?.cancel();
    await _persist();
    await _saveTail.catchError((_) {});
    try {
      await c.assistantConversations.delete(_profileId, row['id'] as String);
      if (!mounted) return;
      if (row['id'] == _conversationId) {
        setState(() {
          _conversationId = uuid();
          _conversationTitle = null;
          _turns.clear();
          _input.clear();
          _recordId = null;
          _recordLabel = null;
        });
      }
      await _loadConversations();
    } catch (_) {
      _storageNotice();
    }
  }

  Future<void> _renameConversation(Json row) async {
    final input = TextEditingController(text: row['title'] as String);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(c.text('重命名对话', 'Rename conversation')),
        content: TextField(controller: input, maxLength: 80, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(c.text('取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, input.text.trim()),
            child: Text(c.text('保存', 'Save')),
          ),
        ],
      ),
    );
    // Dispose after the dialog's exit animation no longer uses the field.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    if (title == null || title.isEmpty || !mounted) return;
    try {
      await _saveTail.catchError((_) {});
      final latest = (await c.assistantConversations.list(_profileId))
          .firstWhere((item) => item['id'] == row['id']);
      await c.assistantConversations.save({...latest, 'title': title});
      if (row['id'] == _conversationId) _conversationTitle = title;
      await _loadConversations();
    } catch (_) {
      _storageNotice();
    }
  }

  Widget _historyDrawer() => Drawer(
    child: SafeArea(
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: FilledButton.tonalIcon(
              key: const ValueKey('assistant-new-chat'),
              icon: const Icon(Icons.add_comment_outlined),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(c.text('新对话', 'New chat')),
              ),
              style: FilledButton.styleFrom(shape: const StadiumBorder()),
              onPressed: _busy || _loading || _switching
                  ? null
                  : _newConversation,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AssistantPrivacyTile(c: c, showDescription: false),
          ),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (!_loading && _conversations.isEmpty)
            ListTile(title: Text(c.text('暂无历史对话', 'No conversations yet'))),
          for (final row in _conversations)
            ListTile(
              selected: row['id'] == _conversationId,
              title: Text(
                row['title'] as String,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              enabled: !_busy && !_loading && !_switching,
              onTap: () => _selectConversation(row),
              trailing: PopupMenuButton<String>(
                enabled: !_busy && !_loading && !_switching,
                onSelected: (value) => value == 'delete'
                    ? _deleteConversation(row)
                    : _renameConversation(row),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Text(c.text('重命名', 'Rename')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(c.text('删除', 'Delete')),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _draftTimer?.cancel();
    unawaited(_persist());
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _showLatest() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  });

  Future<void> _send({
    String? prompt,
    AssistantScope? scope,
    bool retry = false,
  }) async {
    final question = (prompt ?? _input.text).trim();
    if (_busy ||
        _loading ||
        _switching ||
        question.isEmpty ||
        question.length > 1200) {
      return;
    }
    final recordId = _recordId;
    final previous = _turns.lastOrNull;
    final canReuse =
        previous != null &&
        previous.recordId == recordId &&
        previous.error == null &&
        (previous.scope == AssistantScope.question ||
            previous.local ||
            c.assistantRecordsAllowed &&
                previous.consentKey == c.assistantMemoryConsent);
    var resolved = _reader.resolve(
      scope ?? AssistantScope.automatic,
      question,
      hasSelection: recordId != null,
      previous: canReuse ? previous.scope : null,
    );
    setState(() => _busy = true);
    try {
      AssistantContext? evidence;
      Object? readFailure;
      if (resolved != AssistantScope.question && !c.assistantRecordsAllowed) {
        final decision = await _askRecordConsent(context, c);
        if (!mounted || decision == null) return;
        if (decision) {
          if (!await _changeConsent(context, c, true)) return;
        } else {
          resolved = AssistantScope.question;
        }
      }
      final requestConsentRevision = c.assistantConsentRevision;
      final requestConsentKey = c.assistantMemoryConsent;
      if (resolved != AssistantScope.question) {
        try {
          evidence = await _reader.read(
            question,
            resolved,
            recordId: recordId,
            previousQuestion: canReuse && previous.scope == resolved
                ? previous.question
                : null,
          );
        } catch (failure) {
          readFailure = failure;
        }
      }
      if (!mounted) return;
      if (retry && _turns.isNotEmpty && _turns.last.error != null) {
        _turns.removeLast();
      }
      if (prompt == null || _input.text.trim() == question) _input.clear();
      FocusScope.of(context).unfocus();
      setState(() => _pending = question);
      await _persist();
      if (!mounted) return;
      _showLatest();
      final attached = evidence?.evidence.isNotEmpty == true;
      final revision = requestConsentRevision;
      var historyUsesRecords = false;
      bool canSend() =>
          mounted &&
          (!(attached || historyUsesRecords) ||
              c.assistantRecordsAllowed &&
                  revision == c.assistantConsentRevision);
      try {
        if (readFailure != null) throw readFailure;
        if (!canSend()) return;
        if (!c.assistant.available) {
          _turns.add(
            _AssistantTurn(
              question,
              resolved,
              recordId,
              _localReply(question, evidence),
              context: evidence,
              local: true,
              consentRevision: revision,
              consentKey: attached || historyUsesRecords
                  ? requestConsentKey
                  : null,
            ),
          );
          return;
        }
        final lastMatching = <_AssistantTurn>[];
        for (final turn in _turns) {
          if (turn.consentKey != null &&
              (!c.assistantRecordsAllowed ||
                  turn.consentKey != c.assistantMemoryConsent)) {
            lastMatching.clear();
          } else if (turn.reply != null && turn.error == null && !turn.local) {
            lastMatching.add(turn);
          }
        }
        historyUsesRecords = lastMatching.any(
          (turn) => turn.consentKey != null,
        );
        final reply = await c.assistant.ask(
          locale: c.locale,
          question: question,
          requestId: uuid(),
          history: [
            for (final turn in lastMatching) ...[
              {'role': 'user', 'text': turn.question},
              {
                'role': 'assistant',
                'text': [turn.reply!.answer, ?turn.reply!.nextStep].join('\n'),
              },
            ],
          ],
          context: c.assistantRecordsAllowed ? evidence?.toJson() : null,
          canSend: canSend,
          onAnswer: (answer) {
            if (!canSend()) return;
            final follow =
                !_scroll.hasClients || _scroll.position.extentAfter < 96;
            setState(() => _streamedAnswer = answer);
            if (follow) _showLatest();
          },
          installationToken:
              c.settings['assistant_installation_origin'] ==
                  c.assistant.base.toString()
              ? c.settings['assistant_installation_token'] as String?
              : null,
          saveInstallationToken: (token) async {
            try {
              await c.updateSettings(
                values: {
                  'assistant_installation_origin': c.assistant.base.toString(),
                  'assistant_installation_token': token,
                },
              );
            } catch (_) {
              // The gateway can still use the credential for this app session.
            }
          },
        );
        if (!canSend()) return;
        _turns.add(
          _AssistantTurn(
            question,
            resolved,
            recordId,
            reply,
            context: evidence,
            consentRevision: revision,
            consentKey: attached || historyUsesRecords
                ? c.assistantMemoryConsent
                : null,
          ),
        );
      } catch (failure) {
        if (!canSend()) return;
        final code = failure is AssistantFailure ? failure.code : 'records';
        if (code == 'cancelled') return;
        _turns.add(
          _AssistantTurn(
            question,
            resolved,
            recordId,
            null,
            context: c.assistantRecordsAllowed ? evidence : null,
            error: code,
          ),
        );
      }
    } finally {
      if (mounted) {
        final follow = !_scroll.hasClients || _scroll.position.extentAfter < 96;
        setState(() {
          _busy = false;
          _pending = null;
          _streamedAnswer = '';
        });
        await _persist();
        if (follow) _showLatest();
      }
    }
  }

  AssistantReply _localReply(String question, AssistantContext? context) {
    if (context != null) {
      return AssistantReply(
        answer: context.evidence.isEmpty
            ? c.text('没有找到可用的练习记录。', 'No usable practice records were found.')
            : c.text(
                '已整理与问题相关的本机记录。你可以展开下方依据查看数据。',
                'Relevant records from this device are shown below. Expand the references to review your results.',
              ),
        references: {
          for (final (i, item) in context.evidence.indexed)
            i + 1: item.metrics.keys.toSet(),
        },
      );
    }
    final text = question.toLowerCase();
    if (text.contains('提醒') || text.contains('reminder')) {
      return AssistantReply(
        answer: c.text(
          '打开「计划」，点下方加号新建计划，设置重复周期与通知时间。若未收到提醒，可在系统设置检查琴伴通知权限。',
          'Open Plans and use the plus button to create a plan, then choose when it repeats and when to notify you. If a reminder is missing, check notification access in system settings.',
        ),
      );
    }
    if (text.contains('开始练习') || text.contains('start practi')) {
      return AssistantReply(
        answer: c.text(
          '可以从首页的今日推荐开始，也可以打开「练习」选一首喜欢的曲目。练习完成后，到「记录」查看这次表现。',
          'Start with Today’s pick on Home or choose a piece in Practice. Visit History to review the result afterwards.',
        ),
      );
    }
    return AssistantReply(
      answer: c.text('在线问答尚未配置', 'Online Q&A is not configured'),
    );
  }

  Widget _welcome(double centerY) => CustomSingleChildLayout(
    delegate: _WelcomePosition(centerY),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        c.text('今天想聊天什么？', 'What would you like to talk about today?'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    ),
  );

  Widget _message(String value, {bool user = false}) => Align(
    alignment: user ? Alignment.centerRight : Alignment.centerLeft,
    child: QinPanel(soft: user, child: SelectableText(value)),
  );

  Widget _turn(_AssistantTurn turn, {required bool last}) {
    final evidence = turn.context;
    final reply = turn.reply;
    final references =
        reply?.references ??
        {
          for (final (i, item)
              in (evidence?.evidence ?? <AssistantEvidence>[]).indexed)
            i + 1: item.metrics.keys.toSet(),
        };
    final limit = switch (evidence?.limit) {
      'no_records' => c.text(
        '这段时间没有可用记录。',
        'No usable records in this period.',
      ),
      'record_unavailable' => c.text(
        '这条记录暂时无法读取。',
        'This record is unavailable.',
      ),
      'insufficient_comparable' => c.text(
        '同条件样本不足，暂时无法判断趋势。',
        'There are too few comparable results to assess a trend.',
      ),
      'latest_comparable_only' => c.text(
        '比较仅使用同条件的近期样本。',
        'Only recent results under comparable conditions are included.',
      ),
      'latest_sample_only' => c.text(
        '本次摘要只包含部分近期记录。',
        'This summary covers a limited set of recent records.',
      ),
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _message(turn.question, user: true),
        const SizedBox(height: 10),
        QinPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!turn.local) ...[
                Text(
                  c.text('AI 训练助手', 'AI practice assistant'),
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: context.qin.primary),
                ),
                const SizedBox(height: 8),
              ],
              if (reply != null) ...[
                SelectableText(reply.answer),
                if (reply.nextStep?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Text(
                    c.text('下一步', 'Next step'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  SelectableText(reply.nextStep!),
                ],
              ] else ...[
                Text(_errorMessage(turn.error)),
                if (last)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: QinTextButton(
                      onPressed: _busy
                          ? null
                          : () => _send(
                              prompt: turn.question,
                              scope: turn.recordId == _recordId
                                  ? turn.scope
                                  : AssistantScope.automatic,
                              retry: true,
                            ),
                      child: Text(c.text('重试', 'Retry')),
                    ),
                  ),
              ],
              if (limit != null) ...[
                const SizedBox(height: 8),
                Text(limit, style: Theme.of(context).textTheme.bodySmall),
              ],
              if (evidence != null && references.isNotEmpty) ...[
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(c.text('查看参考依据', 'View references')),
                  subtitle: evidence.from == null
                      ? null
                      : Text('${evidence.from} — ${evidence.until}'),
                  children: [
                    for (final entry in references.entries)
                      _source(evidence.evidence[entry.key - 1], entry.value),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _errorMessage(String? code) => switch (code) {
    'quota' => c.text(
      '今天的问答额度已用完，请稍后再试。',
      'The question limit was reached. Try again later.',
    ),
    'interrupted' => c.text(
      '上次回答中断，可重试。',
      'The previous reply was interrupted. You can retry.',
    ),
    'context_too_large' => c.text(
      '这段对话或记录超出服务可处理的容量，请缩小记录日期范围或新建对话。',
      'This conversation or record range exceeds the service capacity. Narrow the dates or start a new chat.',
    ),
    'network' => c.text(
      '暂时无法连接，请检查网络。',
      'Unable to connect. Check your connection.',
    ),
    'timeout' => c.text('等待超时，请重试。', 'The request timed out. Please retry.'),
    'invalid_reply' => c.text(
      '暂未生成可核对的 AI 解读。',
      'An AI response with verifiable references is unavailable.',
    ),
    'records' => c.text('暂时无法读取训练记录。', 'Practice records could not be read.'),
    _ => c.text(
      '在线问答暂不可用，请稍后再试。',
      'Online answers are temporarily unavailable.',
    ),
  };

  Widget _source(AssistantEvidence item, Set<String> fields) => QinListTile(
    surfaceBuilder: (tile) => Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: tile,
    ),
    title: Text(item.title),
    subtitle: Text(
      [
        item.date,
        for (final key in fields)
          '${_metricLabel(key, item.kind)} ${item.metrics[key]}',
      ].join(' · '),
    ),
    trailing: item.recordId == null ? null : const Icon(Icons.chevron_right),
    onTap: item.recordId == null ? null : () => _openRecord(item.recordId!),
  );

  String _metricLabel(String key, String kind) => switch (key) {
    'matched_notes' => c.text('匹配音符', 'Matched notes'),
    'total_notes' => c.text('总音符', 'Total notes'),
    'wrong_keys' => c.text('错键', 'Wrong keys'),
    'tempo_bpm' => 'BPM',
    'valid_samples' => c.text('有效样本', 'Valid samples'),
    'primary_hits' => primaryMetricTitle(kind, c.chinese),
    'primary_total' => c.text('主要指标总数', 'Primary total'),
    'playback_seconds' => c.text('播放秒数', 'Playback seconds'),
    'parts_reached_end' => c.text('已播完部分', 'Parts played to end'),
    'total_parts' => c.text('总部分', 'Total parts'),
    'session_count' => c.text('记录数', 'Records'),
    'target_count' => c.text('目标次数', 'Target count'),
    'target_minutes' => c.text('目标分钟', 'Target minutes'),
    _ => c.text('完成次数', 'Completed count'),
  };

  Future<void> _openRecord(String id) async {
    try {
      final record = await c.repository.detail(id);
      if (!mounted) return;
      if (record != null && record['record_unavailable'] != true) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ResultPage(
              c: c,
              record: record,
              fromHistory: true,
              showAssistant: false,
            ),
          ),
        );
        return;
      }
    } catch (_) {
      // The record may have been deleted after the answer.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(c.text('这条记录暂时无法读取。', 'This record is unavailable.')),
        ),
      );
    }
  }

  Widget _composer(
    double maxHeight, {
    required bool showOfflineNotice,
  }) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: maxHeight),
    child: SingleChildScrollView(
      padding: qinPagePadding(context).copyWith(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_recordId != null)
            Row(
              children: [
                const Icon(Icons.history_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _recordLabel ?? '',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                QinIconButton(
                  tooltip: c.text('移除关联练习', 'Remove selected practice'),
                  icon: const Icon(Icons.close),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _recordId = null),
                ),
              ],
            ),
          if (showOfflineNotice) ...[
            QinStatus(
              text: c.text('在线服务未配置', 'Online service is not configured'),
            ),
            const SizedBox(height: 12),
          ],
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.qin.background,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: context.qin.line),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('assistant-question'),
                      controller: _input,
                      enabled: !_loading && !_switching,
                      onChanged: (_) {
                        _draftTimer?.cancel();
                        _draftTimer = Timer(
                          const Duration(milliseconds: 500),
                          () => unawaited(_persist()),
                        );
                      },
                      textAlignVertical: TextAlignVertical.center,
                      minLines: 1,
                      maxLines: 3,
                      inputFormatters: [LengthLimitingTextInputFormatter(1200)],
                      decoration: InputDecoration(
                        hintText: c.text('输入你的问题', 'Ask a question'),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder(
                    valueListenable: _input,
                    builder: (context, value, _) => QinIconButton(
                      key: const ValueKey('assistant-send'),
                      tooltip: c.text('发送', 'Send'),
                      icon: const Icon(Icons.arrow_circle_up_rounded, size: 36),
                      style: IconButton.styleFrom(
                        foregroundColor: context.qin.primary,
                      ),
                      onPressed:
                          _busy ||
                              _loading ||
                              _switching ||
                              value.text.trim().isEmpty
                          ? null
                          : () => _send(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => Scaffold(
      key: _scaffold,
      drawer: _historyDrawer(),
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: MediaQuery.sizeOf(context).width,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: c.text('历史对话', 'Conversations'),
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffold.currentState?.openDrawer(),
        ),
        title: PageTitle(c.text('AI 训练助手', 'AI practice assistant')),
        actions: [
          IconButton(
            tooltip: c.text('新对话', 'New chat'),
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _busy || _loading || _switching
                ? null
                : _newConversation,
          ),
          IconButton(
            tooltip: c.text('返回', 'Back'),
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.maybePop(context),
          ),
        ],
      ),
      body: QinPageSurface(
        opacity: .92,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const QinPageBackground(
              asset: 'assets/ui_images/41-ai-assistant-background.webp',
              aspectRatio: 941 / 1672,
              fill: true,
              treatment: QinBackgroundTreatment.softenedWithTextGradient,
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final padding = MediaQuery.paddingOf(context);
                final empty = _turns.isEmpty && _pending == null;
                return SafeArea(
                  child: Column(
                    children: [
                      Expanded(
                        child: empty
                            ? _welcome(
                                MediaQuery.sizeOf(context).height / 4 -
                                    padding.top,
                              )
                            : ListView(
                                controller: _scroll,
                                padding: qinPagePadding(context),
                                children: [
                                  for (final (i, turn) in _turns.indexed) ...[
                                    _turn(turn, last: i == _turns.length - 1),
                                    const SizedBox(height: 16),
                                  ],
                                  if (_pending != null) ...[
                                    _message(_pending!, user: true),
                                    const SizedBox(height: 10),
                                    if (_streamedAnswer.isEmpty)
                                      QinStatus(
                                        tone: QinTone.neutral,
                                        text: c.text(
                                          '正在准备回答…',
                                          'Preparing a reply…',
                                        ),
                                      )
                                    else
                                      QinPanel(
                                        child: SelectableText(_streamedAnswer),
                                      ),
                                  ],
                                ],
                              ),
                      ),
                      _composer(
                        (constraints.maxHeight - padding.vertical).clamp(
                              0.0,
                              double.infinity,
                            ) *
                            .7,
                        showOfflineNotice: empty && !c.assistant.available,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _WelcomePosition extends SingleChildLayoutDelegate {
  const _WelcomePosition(this.centerY);

  final double centerY;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    (size.width - childSize.width) / 2,
    (centerY - childSize.height / 2).clamp(0.0, size.height - childSize.height),
  );

  @override
  bool shouldRelayout(_WelcomePosition oldDelegate) =>
      centerY != oldDelegate.centerY;
}
