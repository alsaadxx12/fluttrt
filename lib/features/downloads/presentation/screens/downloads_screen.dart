import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_theme.dart';
import 'package:youtube_downloader/core/localization/app_localizations.dart';
import 'package:youtube_downloader/core/services/file_opener_service.dart';
import 'package:youtube_downloader/core/utils/file_utils.dart';
import 'package:youtube_downloader/core/utils/formatters.dart';
import 'package:youtube_downloader/features/home/presentation/providers/video_analyzer_provider.dart';
import 'package:youtube_downloader/features/settings/presentation/providers/settings_provider.dart';
import 'package:youtube_downloader/features/downloads/data/models/download_task_model.dart';
import 'package:youtube_downloader/features/downloads/presentation/providers/downloads_provider.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloadsState = ref.watch(downloadsProvider);
    final strings = ref.watch(stringsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final allTasks = downloadsState.tasks;
    final activeTasks = downloadsState.activeTasks;
    final completedTasks = downloadsState.completedTasks;
    final failedTasks = downloadsState.failedTasks;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Screen Header & Clear Button
            Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  strings.navDownloads,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                if (allTasks.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _confirmClearAll(context),
                    icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                    label: Text(strings.clearAllHistory, style: const TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Tabs
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  width: 1,
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primary,
                indicatorWeight: 3,
                labelColor: AppColors.primary,
                unselectedLabelColor: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                tabs: [
                  Tab(text: '${strings.tabAll} (${allTasks.length})'),
                  Tab(text: '${strings.tabDownloading} (${activeTasks.length})'),
                  Tab(text: '${strings.tabCompleted} (${completedTasks.length})'),
                  Tab(text: '${strings.tabFailed} (${failedTasks.length})'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTaskList(allTasks, strings, isDark),
                  _buildTaskList(activeTasks, strings, isDark),
                  _buildTaskList(completedTasks, strings, isDark),
                  _buildTaskList(failedTasks, strings, isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskList(List<DownloadTaskModel> list, AppStrings strings, bool isDark) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_download_outlined,
              size: 56,
              color: isDark ? AppColors.darkTextSecondary.withOpacity(0.4) : AppColors.lightTextSecondary.withOpacity(0.4),
            ),
            const SizedBox(height: 12),
            Text(
              strings.noDownloads,
              style: TextStyle(
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        final task = list[index];
        return _DownloadHistoryItem(task: task);
      },
    );
  }

  void _confirmClearAll(BuildContext context) {
    final strings = ref.read(stringsProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.clearAllHistory),
        content: Text(strings.confirmDelete),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(strings.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(downloadsProvider.notifier).clearAll();
              Navigator.pop(ctx);
            },
            child: Text(strings.actionDelete),
          ),
        ],
      ),
    );
  }
}

class _DownloadHistoryItem extends ConsumerWidget {
  final DownloadTaskModel task;

  const _DownloadHistoryItem({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isCompleted = task.status == DownloadStatus.completed;
    final isDownloading = task.status == DownloadStatus.downloading;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(AppTheme.borderRadius),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 64,
              height: 44,
              child: Image.network(
                task.thumbnailUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: isDark ? AppColors.darkSecondaryBg : AppColors.lightSecondaryBg,
                  child: const Icon(Icons.video_library_rounded, color: AppColors.primary, size: 24),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: task.downloadType == DownloadType.video
                            ? AppColors.primary.withOpacity(0.1)
                            : AppColors.info.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        task.qualityLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: task.downloadType == DownloadType.video ? AppColors.primary : AppColors.info,
                        ),
                      ),
                    ),
                    Text(
                      task.format.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                    Text(
                      FileUtils.formatBytes(task.totalBytes > 0 ? task.totalBytes : task.downloadedBytes),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                    Text('•', style: TextStyle(color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
                    Text(
                      Formatters.formatDate(task.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? AppColors.successContainer
                            : (isDownloading ? AppColors.primaryContainer : AppColors.warningContainer),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isCompleted
                            ? strings.tabCompleted
                            : (isDownloading ? strings.tabDownloading : (task.status == DownloadStatus.failed ? 'فشل' : task.status.name)),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isCompleted
                              ? AppColors.success
                              : (isDownloading ? AppColors.primary : AppColors.warning),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 3-dots Menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 20),
            onSelected: (action) async {
              switch (action) {
                case 'open':
                  final ok = await FileOpenerService.openFile(task.filePath);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(strings.fileNotFound)),
                    );
                  }
                  break;
                case 'location':
                  await FileOpenerService.openFolder(task.filePath);
                  break;
                case 'redownload':
                  ref.read(analyzerProvider.notifier).analyze(task.videoUrl);
                  break;
                case 'delete':
                  ref.read(downloadsProvider.notifier).removeTask(task.id);
                  break;
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'open',
                child: Row(
                  children: [
                    const Icon(Icons.play_circle_outline_rounded, size: 18),
                    const SizedBox(width: 10),
                    Text(strings.actionOpen),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'location',
                child: Row(
                  children: [
                    const Icon(Icons.folder_open_rounded, size: 18),
                    const SizedBox(width: 10),
                    Text(strings.actionOpenLocation),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'redownload',
                child: Row(
                  children: [
                    const Icon(Icons.refresh_rounded, size: 18),
                    const SizedBox(width: 10),
                    Text(strings.actionRedownload),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                    const SizedBox(width: 10),
                    Text(strings.actionDelete, style: const TextStyle(color: AppColors.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
