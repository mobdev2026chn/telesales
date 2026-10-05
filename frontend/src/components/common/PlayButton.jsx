// "Play recording" row action (Call Log, User Details)
import ActionIcon from './ActionIcon';

export default function PlayButton({ onClick, label }) {
  return <ActionIcon icon="caret-right" tone="play" label={label} onClick={onClick} />;
}
