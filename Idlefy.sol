// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title  Idlefy
/// @notice Fully onchain to-do list platform built on Botchain.
///         Every wallet owns its own persistent task list stored on-chain.
///         Tasks are scoped to msg.sender — no shared state, no admins.
///         All write functions are paid txs; getTasks() is a free view call.
contract Idlefy {

    // ─── Structs ───────────────────────────────────────────────────────────

    struct Task {
        uint256 id;
        string  text;
        bool    completed;
        uint256 createdAt;
        uint256 completedAt; // 0 if not yet completed
    }

    // ─── Storage ───────────────────────────────────────────────────────────

    /// wallet => list of tasks (ordered by creation)
    mapping(address => Task[]) private _tasks;

    /// wallet => next task id counter
    mapping(address => uint256) private _nextId;

    /// wallet => total tasks ever created (never decremented on delete)
    mapping(address => uint256) public totalCreated;

    /// wallet => total tasks completed
    mapping(address => uint256) public totalCompleted;

    // ─── Events ────────────────────────────────────────────────────────────

    event TaskAdded(
        address indexed owner,
        uint256 indexed taskId,
        string  text,
        uint256 timestamp
    );

    event TaskCompleted(
        address indexed owner,
        uint256 indexed taskId,
        uint256 timestamp
    );

    event TaskReopened(
        address indexed owner,
        uint256 indexed taskId,
        uint256 timestamp
    );

    event TaskDeleted(
        address indexed owner,
        uint256 indexed taskId,
        uint256 timestamp
    );

    event TaskEdited(
        address indexed owner,
        uint256 indexed taskId,
        string  newText,
        uint256 timestamp
    );

    // ─── Write functions ───────────────────────────────────────────────────

    /// @notice Add a new task to the caller's list.
    /// @param  text  The task description.
    function addTask(string calldata text) external {
        require(bytes(text).length > 0, "Idlefy: empty task");

        uint256 id = _nextId[msg.sender]++;

        _tasks[msg.sender].push(Task({
            id:          id,
            text:        text,
            completed:   false,
            createdAt:   block.timestamp,
            completedAt: 0
        }));

        totalCreated[msg.sender]++;

        emit TaskAdded(msg.sender, id, text, block.timestamp);
    }

    /// @notice Mark a task as completed.
    /// @param  taskIndex  Index of the task in the caller's task array.
    function completeTask(uint256 taskIndex) external {
        Task[] storage list = _tasks[msg.sender];
        require(taskIndex < list.length, "Idlefy: index out of range");
        require(!list[taskIndex].completed, "Idlefy: already completed");

        list[taskIndex].completed   = true;
        list[taskIndex].completedAt = block.timestamp;

        totalCompleted[msg.sender]++;

        emit TaskCompleted(msg.sender, list[taskIndex].id, block.timestamp);
    }

    /// @notice Reopen a completed task.
    /// @param  taskIndex  Index of the task in the caller's task array.
    function reopenTask(uint256 taskIndex) external {
        Task[] storage list = _tasks[msg.sender];
        require(taskIndex < list.length, "Idlefy: index out of range");
        require(list[taskIndex].completed, "Idlefy: not completed");

        list[taskIndex].completed   = false;
        list[taskIndex].completedAt = 0;

        if (totalCompleted[msg.sender] > 0) {
            totalCompleted[msg.sender]--;
        }

        emit TaskReopened(msg.sender, list[taskIndex].id, block.timestamp);
    }

    /// @notice Edit the text of an existing task.
    /// @param  taskIndex  Index of the task in the caller's task array.
    /// @param  newText    The updated task text.
    function editTask(uint256 taskIndex, string calldata newText) external {
        Task[] storage list = _tasks[msg.sender];
        require(taskIndex < list.length, "Idlefy: index out of range");
        require(bytes(newText).length > 0, "Idlefy: empty text");

        list[taskIndex].text = newText;

        emit TaskEdited(msg.sender, list[taskIndex].id, newText, block.timestamp);
    }

    /// @notice Delete a task. Swaps with last element then pops (gas-efficient).
    /// @param  taskIndex  Index of the task in the caller's task array.
    function deleteTask(uint256 taskIndex) external {
        Task[] storage list = _tasks[msg.sender];
        require(taskIndex < list.length, "Idlefy: index out of range");

        uint256 deletedId = list[taskIndex].id;

        // if the deleted task was completed, decrement counter
        if (list[taskIndex].completed && totalCompleted[msg.sender] > 0) {
            totalCompleted[msg.sender]--;
        }

        // swap with last and pop
        list[taskIndex] = list[list.length - 1];
        list.pop();

        emit TaskDeleted(msg.sender, deletedId, block.timestamp);
    }

    // ─── View functions (free) ─────────────────────────────────────────────

    /// @notice Returns all tasks for the caller.
    function getTasks() external view returns (Task[] memory) {
        return _tasks[msg.sender];
    }

    /// @notice Returns all tasks for any wallet (public read).
    function getTasksOf(address owner) external view returns (Task[] memory) {
        return _tasks[owner];
    }

    /// @notice Returns the total number of tasks currently in the caller's list.
    function getTaskCount() external view returns (uint256) {
        return _tasks[msg.sender].length;
    }

    /// @notice Returns the number of pending (incomplete) tasks for the caller.
    function getPendingCount() external view returns (uint256 count) {
        Task[] memory list = _tasks[msg.sender];
        for (uint256 i; i < list.length; i++) {
            if (!list[i].completed) count++;
        }
    }

    /// @notice Returns a single task by its array index for the caller.
    function getTask(uint256 taskIndex) external view returns (Task memory) {
        require(taskIndex < _tasks[msg.sender].length, "Idlefy: index out of range");
        return _tasks[msg.sender][taskIndex];
    }

    /// @notice Returns a paginated slice of the caller's task list.
    function getTasksPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (Task[] memory page)
    {
        Task[] storage list = _tasks[msg.sender];
        uint256 end = offset + limit > list.length ? list.length : offset + limit;
        if (offset >= list.length) return page;
        page = new Task[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            page[i - offset] = list[i];
        }
    }
}
